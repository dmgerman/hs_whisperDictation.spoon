# query-model.py

Command-line tool to query an LLM. Works as a stdin/stdout filter for use with WhisperDictation's post-transcription filters.

## Usage

```bash
# Answer a question
echo "What is Hammerspoon?" | query-model.py answer

# Filter text through a prompt
echo "some text" | query-model.py filter -p "Correct the grammar"

# Send raw input to the LLM
echo "Translate to French: hello" | query-model.py raw
```

## Backend Selection

The script auto-detects available backends in this order:

1. **Remote LLM** — checks `REMOTE_LLM_HOST` (configurable, default: `iridium.dmg`) on port 1234
2. **Local LLM** — checks `localhost:1234` (e.g., LM Studio)
3. **ChatGPT** — uses OpenAI API (requires API key)

Override with `--backend`:

```bash
query-model.py --backend local answer "question"
query-model.py --backend chatgpt filter -p "translate to Spanish"
```

## Configuration

Edit the variables at the top of the script:

```python
# Remote LLM host to try before localhost. Set to "" to skip.
REMOTE_LLM_HOST = "iridium.dmg"
LOCAL_LLM_PORT = 1234
```

Set `REMOTE_LLM_HOST = None` to only check localhost.

## Requirements

- Python 3
- `pip install requests`
- For ChatGPT: OpenAI API key stored in `~/.authinfo.gpg` (gpg-encrypted, machine `api.openai.com`)
- For local: LM Studio or compatible OpenAI-API server on port 1234

## Subcommands

| Command  | Description                        | Requires `-p` |
|----------|------------------------------------|---------------|
| `answer` | Answer a question succinctly       | No (optional) |
| `filter` | Apply a custom prompt to the input | Yes           |
| `raw`    | Send input as-is to the LLM       | No            |

## Options

| Flag              | Description                            |
|-------------------|----------------------------------------|
| `--backend`       | Force backend: `auto`, `local`, `chatgpt` |
| `-t`, `--think`   | Include `<think>` blocks in output     |
| `-d`, `--debug`   | Print raw JSON response to stderr      |
| `-f`, `--file`    | Read input from file instead of stdin  |
| `-p`, `--prompt`  | Custom prompt (required for `filter`)  |

## License

Copyright (c) 2026 Daniel M. German. MIT License.
