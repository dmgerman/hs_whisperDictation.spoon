#!/usr/bin/env python3
#
# query-model.py - Query an LLM (local or ChatGPT) via command line
#
# Copyright (c) 2026 Daniel M. German
# MIT License - See LICENSE file for details
#

import argparse
import json
import re
import socket
import subprocess
import sys
import requests


# Configuration
# Remote LLM host to try before localhost. Set to "" to skip.
REMOTE_LLM_HOST = "iridium.dmg"
LOCAL_LLM_PORT = 1234


def get_openai_api_key():
    cmd = 'gpg --decrypt ~/.authinfo.gpg 2> /dev/null | grep "machine api.openai.com" | cut -d " " -f 6'
    result = subprocess.run(['bash', '-c', cmd], stdout=subprocess.PIPE, text=True)
    key = result.stdout.strip()
    if not key:
        print("Error: Could not retrieve OpenAI API key.", file=sys.stderr)
        sys.exit(1)
    return key


def is_reachable(host, port, timeout=1):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (socket.timeout, ConnectionRefusedError, OSError):
        return False


def get_local_model(base_url):
    response = requests.get(f"{base_url}/v1/models", timeout=5)
    models = response.json().get('data', [])
    if not models:
        print("Error: No models loaded in LM Studio.", file=sys.stderr)
        sys.exit(1)
    return models[0]['id']


def try_local():
    for host in filter(None, [REMOTE_LLM_HOST, "localhost"]):
        if is_reachable(host, LOCAL_LLM_PORT):
            base_url = f"http://{host}:{LOCAL_LLM_PORT}"
            return base_url, get_local_model(base_url), None
    return None


def try_chatgpt():
    if is_reachable("api.openai.com", 443):
        return "https://api.openai.com", "gpt-4o-mini", get_openai_api_key()
    return None


def resolve_backend(backend):
    if backend == "local":
        result = try_local()
        if result:
            return result
        print("Error: No local LLM reachable.", file=sys.stderr)
        sys.exit(1)

    if backend == "chatgpt":
        result = try_chatgpt()
        if result:
            return result
        # no network — fall back to local
        result = try_local()
        if result:
            return result
        print("Error: No backend reachable (no network and no local LLM).", file=sys.stderr)
        sys.exit(1)

    # auto mode: try local first, then chatgpt
    result = try_local()
    if result:
        return result
    result = try_chatgpt()
    if result:
        return result
    print("Error: No backend reachable (tried local LLM and ChatGPT).", file=sys.stderr)
    sys.exit(1)


def strip_think(text):
    return re.sub(r'<think>.*?</think>\s*', '', text, flags=re.DOTALL)


def query_llm(base_url, model, api_key, message, debug=False):
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    data = {
        "model": model,
        "messages": [{"role": "user", "content": message}]
    }

    response = requests.post(f"{base_url}/v1/chat/completions", headers=headers, json=data)
    response_data = response.json()

    if debug:
        print(json.dumps(response_data, indent=2), file=sys.stderr)

    if 'choices' in response_data:
        return response_data['choices'][0]['message']['content']
    if 'error' in response_data:
        print(f"Error from LLM: {response_data['error']}", file=sys.stderr)
        sys.exit(1)
    print(f"Unexpected response: {response_data}", file=sys.stderr)
    sys.exit(1)


def read_input(args):
    if hasattr(args, 'input') and args.input:
        return args.input
    if args.file:
        try:
            with open(args.file, 'r') as f:
                return f.read()
        except FileNotFoundError:
            print(f"Error: File '{args.file}' not found.", file=sys.stderr)
            sys.exit(1)
    if not sys.stdin.isatty():
        return sys.stdin.read()
    print("Error: No input provided. Pass text as argument, use -f, or pipe via stdin.", file=sys.stderr)
    sys.exit(1)


def parse_args():
    parser = argparse.ArgumentParser(description="Query an LLM (local or ChatGPT)")
    parser.add_argument('--backend', choices=['auto', 'local', 'chatgpt'], default='auto',
                        help="Backend to use (default: auto-detect)")
    parser.add_argument('-t', '--think', action='store_true',
                        help="Include <think> block in output")
    parser.add_argument('-d', '--debug', action='store_true',
                        help="Print raw JSON response to stderr")
    parser.add_argument('-f', '--file', help="Read input from file")

    subparsers = parser.add_subparsers(dest='command', required=True)

    # answer subcommand
    answer_parser = subparsers.add_parser('answer', help="Answer a question succinctly")
    answer_parser.add_argument('input', nargs='?', help="The question to answer")
    answer_parser.add_argument('-p', '--prompt', help="Override the default prompt")

    # filter subcommand
    filter_parser = subparsers.add_parser('filter', help="Filter text through a custom prompt")
    filter_parser.add_argument('input', nargs='?', help="The text to filter")
    filter_parser.add_argument('-p', '--prompt', required=True, help="The prompt to apply")

    # raw subcommand
    raw_parser = subparsers.add_parser('raw', help="Send input as-is to the LLM")
    raw_parser.add_argument('input', nargs='?', help="The text to send")

    return parser.parse_args()


def main():
    args = parse_args()

    input_text = read_input(args)
    base_url, model, api_key = resolve_backend(args.backend)

    if args.command == 'answer':
        prompt = args.prompt or "Answer the following question succinctly in one or few sentences:"
        message = f"{prompt} '{input_text}'"
    elif args.command == 'filter':
        message = f"{args.prompt}: '{input_text}'"
    elif args.command == 'raw':
        message = input_text

    result = query_llm(base_url, model, api_key, message, debug=args.debug)

    if not args.think:
        result = strip_think(result)

    print(result)


if __name__ == '__main__':
    main()
