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
import numpy as np
from pathlib import Path


# === Configuration Constants ===
SILENCE_AMPLITUDE_THRESHOLD = 0.01
PERFECT_SILENCE_DURATION = 3.0
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

    def __init__(self, output_dir, filename_prefix,
                 silence_threshold=5.0,
                 min_chunk_duration=10.0,
                 max_chunk_duration=120.0,
                 sample_rate=16000):
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

        # Silence detection state
        self.silence_start_time = None
        self.perfect_silence_start_time = None
        self.mic_warning_shown = False
        self.startup_silence_check_done = False

        # Control
        self.running = True

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

    def _detect_voice_activity(self, audio_chunk):
        """Detect if audio chunk contains voice using Silero VAD."""
        try:
            import torch
            audio_float = normalize_audio(audio_chunk)
            audio_tensor = torch.from_numpy(audio_float)
            speech_prob = self.vad_model(audio_tensor, self.sample_rate).item()
            return speech_prob > VAD_SPEECH_THRESHOLD
        except Exception as e:
            output_error(f"VAD detection error: {e}")
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
        """Check for perfect silence at startup only."""
        # Only check during startup period
        if self.startup_silence_check_done:
            return

        if not is_perfect_silence(audio_chunk):
            # Audio detected, stop checking
            self.startup_silence_check_done = True
            self.perfect_silence_start_time = None
            return

        if self.perfect_silence_start_time is None:
            self.perfect_silence_start_time = time.time()
            return

        silence_duration = time.time() - self.perfect_silence_start_time
        if silence_duration >= PERFECT_SILENCE_DURATION and not self.mic_warning_shown:
            output_event("silence_warning",
                        message="Perfect silence detected - microphone may be off")
            self.mic_warning_shown = True
            self.startup_silence_check_done = True

    def _emit_chunk_ready(self, chunk_file, is_final=False):
        """Emit chunk_ready event."""
        if chunk_file:
            output_event("chunk_ready",
                        chunk_num=self.chunk_num,
                        audio_file=chunk_file,
                        is_final=is_final)

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
            output_error(f"Audio callback status: {status}")

        # Extract mono audio
        audio_chunk = indata[:, 0].copy()

        # Debug: log first callback
        if len(self.current_chunk_audio) == 0:
            output_debug(f"First audio callback: frames={frames}, shape={indata.shape}")

        # Check for mic off
        self._check_perfect_silence(audio_chunk)

        # Add to current chunk
        self.current_chunk_audio.append(audio_chunk)

        # Debug: log buffer count every 10 callbacks
        if len(self.current_chunk_audio) % 10 == 0:
            output_debug(f"Audio buffers: {len(self.current_chunk_audio)}")

        # Check max duration boundary
        if self._check_max_duration():
            return

        # Check VAD-based silence boundary
        recent_audio = self._get_recent_audio()
        if recent_audio is not None:
            self._process_vad(recent_audio)
            self._check_silence_boundary()

    def start(self):
        """Start continuous recording."""
        import sounddevice as sd

        output_debug(f"start() called, sample_rate={self.sample_rate}")
        self.current_chunk_start_time = time.time()
        output_event("recording_started")

        signal.signal(signal.SIGINT, lambda sig, frame: setattr(self, 'running', False))
        signal.signal(signal.SIGTERM, lambda sig, frame: setattr(self, 'running', False))

        try:
            output_debug("Starting InputStream")
            with sd.InputStream(callback=self.audio_callback,
                              channels=1,
                              samplerate=self.sample_rate,
                              blocksize=int(self.sample_rate * 0.5),
                              dtype=np.float32):
                output_debug("InputStream started, entering loop")
                while self.running:
                    time.sleep(0.1)
                output_debug(f"Exiting loop, running={self.running}")
        except Exception as e:
            output_debug(f"Exception in start(): {e}")
            output_error(f"Recording error: {e}")
        finally:
            output_debug("Finally block, calling _finalize_recording")
            self._finalize_recording()

    def _finalize_recording(self):
        """Save final chunk and emit recording_stopped event."""
        output_debug(f"_finalize_recording: have audio buffers: {len(self.current_chunk_audio)}")
        if self.current_chunk_audio:
            output_debug("Saving final chunk")
            chunk_file = self._save_chunk()
            output_debug(f"Final chunk saved: {chunk_file}")
            self._emit_chunk_ready(chunk_file, is_final=True)
        else:
            output_debug("No audio to save in final chunk")
        output_event("recording_stopped")


# === Main ===

def main():
    parser = argparse.ArgumentParser(
        description="Continuous audio recording with Silero VAD"
    )
    parser.add_argument("--check-deps", action="store_true",
                       help="Check dependencies and exit")
    parser.add_argument("--output-dir", help="Output directory for chunks")
    parser.add_argument("--filename-prefix", help="Prefix for chunk filenames")
    parser.add_argument("--silence-threshold", type=float, default=5.0,
                       help="Silence duration to trigger chunk (seconds)")
    parser.add_argument("--min-chunk-duration", type=float, default=10.0,
                       help="Minimum chunk duration (seconds)")
    parser.add_argument("--max-chunk-duration", type=float, default=120.0,
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
        output_error("Missing required arguments")
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        recorder = ContinuousRecorder(
            args.output_dir,
            args.filename_prefix,
            args.silence_threshold,
            args.min_chunk_duration,
            args.max_chunk_duration
        )
        recorder.start()
    except Exception as e:
        output_error(str(e))
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
