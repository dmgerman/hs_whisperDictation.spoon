#!/usr/bin/env python3
"""
Continuous audio recording with Silero VAD for chunk detection.

Outputs JSON events to stdout for Hammerspoon integration.
"""

import sys
import json
import argparse
import time
import signal
import socket
import threading
import numpy as np
from pathlib import Path


# === Configuration Constants ===
SILENCE_AMPLITUDE_THRESHOLD = 0.01
PERFECT_SILENCE_DURATION_AT_START = 2.0  # Detect mic off at recording start
VAD_SPEECH_THRESHOLD = 0.5
VAD_WINDOW_SECONDS = 0.5


# === Event Output ===

def output_event(event_type, **kwargs):
    """Output a JSON event to stdout."""
    event = {"type": event_type, **kwargs}
    print(json.dumps(event), flush=True)


def output_error(error_msg):
    """Output an error event."""
    output_event("error", error=str(error_msg))

def output_debug(msg):
    """Output a debug event."""
    output_event("debug", message=str(msg))


# === TCP Server ===

class TCPServer:
    """TCP server for sending events to Hammerspoon client."""

    def __init__(self, port):
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind(('127.0.0.1', port))
        self.server_socket.listen(1)
        self.client_socket = None
        self.port = port

    def wait_for_client(self, timeout=10):
        """Accept single client connection with timeout."""
        self.server_socket.settimeout(timeout)
        try:
            self.client_socket, addr = self.server_socket.accept()
            self.client_socket.settimeout(None)  # Blocking mode for send
            return True
        except socket.timeout:
            return False

    def send_event(self, event_type, **kwargs):
        """Send JSON event with newline delimiter.

        Returns False if client disconnected, True otherwise.
        """
        if self.client_socket:
            event = {"type": event_type, **kwargs}
            message = json.dumps(event) + "\n"
            try:
                self.client_socket.sendall(message.encode('utf-8'))
                return True
            except (BrokenPipeError, ConnectionResetError, OSError):
                # Client disconnected
                return False
        return True

    def receive_command(self, timeout=0.1):
        """Receive a command from client (non-blocking).

        Returns command dict if received, None otherwise.
        """
        if not self.client_socket:
            return None

        try:
            self.client_socket.settimeout(timeout)
            data = self.client_socket.recv(1024)
            if not data:
                # Client disconnected
                return {'command': 'disconnect'}

            # Parse JSON command (newline-delimited)
            for line in data.decode('utf-8').split('\n'):
                line = line.strip()
                if line:
                    try:
                        return json.loads(line)
                    except json.JSONDecodeError:
                        pass
        except socket.timeout:
            # No data available (normal)
            return None
        except (ConnectionResetError, BrokenPipeError):
            # Client disconnected
            return {'command': 'disconnect'}

        return None

    def wait_for_reconnect(self, timeout=None):
        """Wait for a new client connection after previous client disconnected.

        Returns True if client connected, False on timeout.
        """
        if self.client_socket:
            # Close old connection
            try:
                self.client_socket.close()
            except:
                pass
            self.client_socket = None

        self.server_socket.settimeout(timeout)
        try:
            self.client_socket, addr = self.server_socket.accept()
            self.client_socket.settimeout(None)
            return True
        except socket.timeout:
            return False

    def close(self):
        """Close server and client sockets."""
        if self.client_socket:
            try:
                self.client_socket.close()
            except:
                pass
            self.client_socket = None
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass


# === Dependency Checking ===

def check_dependencies():
    """Check if all required dependencies are installed."""
    missing = []

    try:
        import sounddevice
    except ImportError:
        missing.append("sounddevice (install: pip install sounddevice)")

    has_torch = False
    has_onnx = False
    try:
        import torch
        has_torch = True
    except ImportError:
        pass

    try:
        import onnxruntime
        has_onnx = True
    except ImportError:
        pass

    if not has_torch and not has_onnx:
        missing.append("torch or onnxruntime (install: pip install torch OR pip install onnxruntime)")

    try:
        import scipy.io.wavfile
    except ImportError:
        missing.append("scipy (install: pip install scipy)")

    return missing


# === Audio Processing Helpers ===

def normalize_audio(audio_chunk):
    """Normalize audio to float32 [-1, 1] range."""
    if audio_chunk.dtype == np.int16:
        return audio_chunk.astype(np.float32) / 32768.0
    return audio_chunk.astype(np.float32)


def is_perfect_silence(audio_chunk):
    """Check if audio is essentially zero (microphone off)."""
    audio_float = normalize_audio(audio_chunk)
    max_amplitude = np.max(np.abs(audio_float))
    return max_amplitude < SILENCE_AMPLITUDE_THRESHOLD


def convert_to_int16(audio_data):
    """Convert audio to int16 format for WAV file."""
    if audio_data.dtype == np.float32 or audio_data.dtype == np.float64:
        return (audio_data * 32767).astype(np.int16)
    return audio_data


# === Continuous Recorder ===

class ContinuousRecorder:
    """Records audio continuously and detects chunk boundaries using Silero VAD."""

    def __init__(self, tcp_server, output_dir, filename_prefix,
                 silence_threshold=5.0,
                 min_chunk_duration=10.0,
                 max_chunk_duration=120.0,
                 sample_rate=16000):
        self.tcp_server = tcp_server
        self.output_dir = Path(output_dir)
        self.filename_prefix = filename_prefix
        self.silence_threshold = silence_threshold
        self.min_chunk_duration = min_chunk_duration
        self.max_chunk_duration = max_chunk_duration
        self.sample_rate = sample_rate

        # Chunk state
        self.chunk_num = 0
        self.current_chunk_audio = []
        self.current_chunk_start_time = None

        # Full recording (all audio for single file save)
        self.all_audio = []

        # Silence detection state
        self.silence_start_time = None
        self.perfect_silence_start_time = None
        self.mic_warning_shown = False
        self.startup_silence_check_done = False

        # Control
        self.running = True
        self.recording = False  # Whether currently recording
        self.mic_off = False  # Track if stopped due to mic being off

        # Load VAD model
        self.vad_model = self._load_vad_model()

    def _load_vad_model(self):
        """Load Silero VAD model."""
        try:
            import torch
            model, _ = torch.hub.load(
                repo_or_dir='snakers4/silero-vad',
                model='silero_vad',
                force_reload=False,
                onnx=False,
                trust_repo=True
            )
            model.eval()
            return model
        except Exception as e:
            raise ImportError(f"Failed to load Silero VAD model: {e}")

    def _reset_recording_state(self):
        """Reset state for a new recording session."""
        self.chunk_num = 0
        self.current_chunk_audio = []
        self.current_chunk_start_time = None
        self.all_audio = []
        self.silence_start_time = None
        self.perfect_silence_start_time = None
        self.mic_warning_shown = False
        self.startup_silence_check_done = False
        self.mic_off = False

    def _detect_voice_activity(self, audio_chunk):
        """Detect if audio chunk contains voice using Silero VAD."""
        try:
            import torch
            audio_float = normalize_audio(audio_chunk)
            audio_tensor = torch.from_numpy(audio_float)
            speech_prob = self.vad_model(audio_tensor, self.sample_rate).item()
            return speech_prob > VAD_SPEECH_THRESHOLD
        except Exception as e:
            self.tcp_server.send_event("error", error=f"VAD detection error: {e}")
            return True  # Assume speech to avoid losing audio

    def _save_chunk(self):
        """Save current chunk audio to WAV file."""
        if not self.current_chunk_audio:
            return None

        self.chunk_num += 1
        chunk_file = self.output_dir / f"{self.filename_prefix}_chunk_{self.chunk_num:03d}.wav"

        audio_data = np.concatenate(self.current_chunk_audio)
        audio_data = convert_to_int16(audio_data)

        import scipy.io.wavfile
        scipy.io.wavfile.write(str(chunk_file), self.sample_rate, audio_data)

        # Reset for next chunk
        self.current_chunk_audio = []
        self.current_chunk_start_time = time.time()

        return str(chunk_file)

    def _check_perfect_silence(self, audio_chunk):
        """Check for perfect silence at startup only - verify mic is working."""
        # Only check during startup period
        if self.startup_silence_check_done:
            return

        if not is_perfect_silence(audio_chunk):
            # Audio detected, mic is working - stop checking
            self.startup_silence_check_done = True
            self.perfect_silence_start_time = None
            return

        if self.perfect_silence_start_time is None:
            self.perfect_silence_start_time = time.time()
            return

        silence_duration = time.time() - self.perfect_silence_start_time
        if silence_duration >= PERFECT_SILENCE_DURATION_AT_START:
            # Microphone is off at startup - stop recording immediately
            self.tcp_server.send_event("silence_warning",
                                      message="Microphone off - stopping recording")
            self.mic_off = True  # Flag that mic is off
            self.running = False  # Stop recording
            self.startup_silence_check_done = True  # Don't check again

    def _emit_chunk_ready(self, chunk_file, is_final=False):
        """Emit chunk_ready event."""
        if chunk_file:
            if not self.tcp_server.send_event("chunk_ready",
                                             chunk_num=self.chunk_num,
                                             audio_file=chunk_file,
                                             is_final=is_final):
                # Client disconnected, stop recording
                self.running = False

    def _check_max_duration(self):
        """Check if chunk exceeded max duration and save if needed."""
        chunk_duration = time.time() - self.current_chunk_start_time
        if chunk_duration >= self.max_chunk_duration:
            chunk_file = self._save_chunk()
            self._emit_chunk_ready(chunk_file, is_final=False)
            return True
        return False

    def _get_recent_audio(self):
        """Get recent audio for VAD analysis."""
        # Silero VAD requires exactly 512 samples for 16kHz
        vad_samples = 512
        recent_audio = np.concatenate(self.current_chunk_audio[-10:])

        if len(recent_audio) >= vad_samples:
            return recent_audio[-vad_samples:]
        return None

    def _check_silence_boundary(self):
        """Check if silence threshold reached and save chunk if needed."""
        chunk_duration = time.time() - self.current_chunk_start_time

        if self.silence_start_time is None:
            return False

        silence_duration = time.time() - self.silence_start_time
        if silence_duration >= self.silence_threshold:
            if chunk_duration >= self.min_chunk_duration:
                chunk_file = self._save_chunk()
                self._emit_chunk_ready(chunk_file, is_final=False)
                self.silence_start_time = None
                return True
        return False

    def _process_vad(self, recent_audio):
        """Process VAD and update silence tracking."""
        has_voice = self._detect_voice_activity(recent_audio)

        if has_voice:
            self.silence_start_time = None
        else:
            if self.silence_start_time is None:
                self.silence_start_time = time.time()

    def audio_callback(self, indata, frames, time_info, status):
        """Callback for sounddevice audio stream."""
        if status:
            self.tcp_server.send_event("error", error=f"Audio callback status: {status}")

        # Only process audio if actively recording
        if not self.recording:
            return

        # Extract mono audio
        audio_chunk = indata[:, 0].copy()

        # Check for mic off
        self._check_perfect_silence(audio_chunk)

        # Add to current chunk
        self.current_chunk_audio.append(audio_chunk)
        # Also accumulate for complete recording file
        self.all_audio.append(audio_chunk)

        # Check max duration boundary
        if self._check_max_duration():
            return

        # Check VAD-based silence boundary
        recent_audio = self._get_recent_audio()
        if recent_audio is not None:
            self._process_vad(recent_audio)
            self._check_silence_boundary()

    def start(self):
        """Start persistent recording server (supports multiple recording sessions)."""
        import sounddevice as sd

        signal.signal(signal.SIGINT, lambda sig, frame: setattr(self, 'running', False))
        signal.signal(signal.SIGTERM, lambda sig, frame: setattr(self, 'running', False))

        try:
            # Keep audio stream running persistently
            with sd.InputStream(callback=self.audio_callback,
                              channels=1,
                              samplerate=self.sample_rate,
                              blocksize=int(self.sample_rate * 0.5),
                              dtype=np.float32):

                # Send server_ready event
                self.tcp_server.send_event("server_ready")

                # Main command loop - server stays running
                while self.running:
                    # Check for commands from client
                    cmd = self.tcp_server.receive_command(timeout=0.1)
                    if cmd:
                        command = cmd.get('command')

                        if command == 'start_recording':
                            if not self.recording:
                                # Start new recording session
                                self._reset_recording_state()
                                self.recording = True
                                self.current_chunk_start_time = time.time()

                                # Give stream a moment to stabilize
                                time.sleep(0.3)

                                self.tcp_server.send_event("recording_started")

                        elif command == 'stop_recording':
                            if self.recording:
                                # Stop current recording session
                                self.recording = False
                                self._finalize_recording()

                        elif command == 'shutdown':
                            # Shutdown server
                            self.running = False

                        elif command == 'disconnect':
                            # Client disconnected - stay running and wait for reconnect
                            if self.recording:
                                # Save current recording
                                self.recording = False
                                self._finalize_recording()
                            # Wait for new client
                            if not self.tcp_server.wait_for_reconnect(timeout=60):
                                # No client after timeout, shutdown
                                self.running = False

        except Exception as e:
            self.tcp_server.send_event("error", error=f"Recording error: {e}")
            # If we were recording, save what we have
            if self.recording:
                self.recording = False
                self._finalize_recording()

    def _save_complete_recording(self):
        """Save complete recording as single timestamped file."""
        if not self.all_audio:
            return None

        from datetime import datetime
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        complete_file = self.output_dir / f"{self.filename_prefix}-{timestamp}.wav"

        audio_data = np.concatenate(self.all_audio)
        audio_data = convert_to_int16(audio_data)

        import scipy.io.wavfile
        scipy.io.wavfile.write(str(complete_file), self.sample_rate, audio_data)

        return str(complete_file)

    def _finalize_recording(self):
        """Save final chunk and emit recording_stopped event."""
        # Save complete recording as single file (for auditing/re-processing)
        complete_file = self._save_complete_recording()
        if complete_file:
            # Notify Lua about complete file path (for saving matching .txt file)
            self.tcp_server.send_event("complete_file", file_path=complete_file)

        # Don't save or transcribe final chunk if mic was off
        if self.mic_off:
            self.tcp_server.send_event("recording_stopped")
            return

        if self.current_chunk_audio:
            chunk_file = self._save_chunk()
            self._emit_chunk_ready(chunk_file, is_final=True)

        self.tcp_server.send_event("recording_stopped")


# === Main ===

def main():
    parser = argparse.ArgumentParser(
        description="Continuous audio recording with Silero VAD"
    )
    parser.add_argument("--check-deps", action="store_true",
                       help="Check dependencies and exit")
    parser.add_argument("--tcp-port", type=int, default=12341,
                       help="TCP server port")
    parser.add_argument("--output-dir", help="Output directory for chunks")
    parser.add_argument("--filename-prefix", help="Prefix for chunk filenames")
    parser.add_argument("--silence-threshold", type=float, default=2.0,
                       help="Silence duration to trigger chunk (seconds)")
    parser.add_argument("--min-chunk-duration", type=float, default=3.0,
                       help="Minimum chunk duration (seconds)")
    parser.add_argument("--max-chunk-duration", type=float, default=600.0,
                       help="Maximum chunk duration (seconds)")

    args = parser.parse_args()

    if args.check_deps:
        missing = check_dependencies()
        if missing:
            print(json.dumps({"status": "error", "missing": missing}))
            sys.exit(1)
        print(json.dumps({"status": "ok"}))
        sys.exit(0)

    if not args.output_dir or not args.filename_prefix:
        print(json.dumps({"status": "error", "error": "Missing required arguments"}),
              file=sys.stderr, flush=True)
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    tcp_server = None
    try:
        # Start TCP server
        tcp_server = TCPServer(args.tcp_port)
        print(json.dumps({"status": "listening", "port": args.tcp_port}),
              file=sys.stderr, flush=True)

        # Wait for client connection
        if not tcp_server.wait_for_client(timeout=10):
            print(json.dumps({"status": "error", "error": "Client connection timeout"}),
                  file=sys.stderr, flush=True)
            sys.exit(1)

        # Start recording
        recorder = ContinuousRecorder(
            tcp_server,
            args.output_dir,
            args.filename_prefix,
            args.silence_threshold,
            args.min_chunk_duration,
            args.max_chunk_duration
        )
        recorder.start()
    except Exception as e:
        error_msg = str(e)
        if tcp_server:
            tcp_server.send_event("error", error=error_msg)
        print(json.dumps({"status": "error", "error": error_msg}),
              file=sys.stderr, flush=True)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)
    finally:
        if tcp_server:
            tcp_server.close()


if __name__ == "__main__":
    main()
