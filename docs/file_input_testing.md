# File Input Testing Mode

The whisper_stream.py script supports a **file input test mode** that allows testing the full audio processing pipeline with pre-recorded WAV files instead of live microphone input.

## Purpose

This mode enables:
- **Deterministic testing** - Use known audio files with predictable content
- **Automated integration testing** - Test VAD, chunking, and transcription without manual recording
- **Floor level calibration** - Test silence detection with various noise floors
- **Chunk boundary testing** - Verify chunk splitting with controlled silence patterns
- **Faster development** - No need to record audio repeatedly during testing

## Usage

### Command Line

```bash
python whisper_stream.py \
  --test-file path/to/audio.wav \
  --output-dir /tmp/test_output \
  --filename-prefix test \
  --tcp-port 12341
```

### Python API

```python
from whisper_stream import FileAudioSource, ContinuousRecorder, TCPServer

# Create file audio source
audio_source = FileAudioSource("tests/fixtures/audio/chunks/chunk_short.wav")

# Create recorder with file source
recorder = ContinuousRecorder(
    tcp_server=tcp_server,
    output_dir="output",
    filename_prefix="test",
    audio_source=audio_source  # Pass file source instead of using microphone
)

recorder.start()
```

## File Requirements

- **Format**: WAV files (mono or stereo)
- **Sample Rate**: Any (will be resampled to 16kHz)
- **Bit Depth**: 16-bit or float32
- **Duration**: Any length

The FileAudioSource class will automatically:
- Convert stereo to mono (uses first channel)
- Resample to 16kHz if needed
- Normalize to float32 [-1, 1] range
- Chunk into 0.5-second blocks (matching sounddevice behavior)

## How It Works

1. **FileAudioSource** loads the WAV file and prepares it for streaming
2. Audio is chunked into 0.5-second blocks (8000 samples at 16kHz)
3. Chunks are fed to the same `audio_callback` used by microphone input
4. All processing (VAD, chunking, events) works identically to microphone mode
5. The recorder respects `start_recording`/`stop_recording` commands

### Differences from Microphone Mode

- No real-time delay (chunks are processed as fast as possible)
- Audio ends when file is exhausted (sends EOF)
- No sounddevice dependency required
- Signal handlers are skipped (safe for background threads in tests)

## Test Audio Files

The project includes test audio files in:
- `tests/fixtures/audio/chunks/` - Short test chunks (3-8 seconds)
  - `chunk_short.wav` - 8 seconds
  - `chunk_medium.wav` - 4.5 seconds
  - `chunk_long.wav` - 3 seconds
- `tests/fixtures/audio/complete/` - Full recordings
- `tests/data/audio/recordings/` - Real recordings for integration testing

## Integration Tests

See `tests/python/test_file_integration.py` for examples:

```python
def test_process_audio_file():
    """Test processing a complete audio file."""
    # Create file source
    audio_source = FileAudioSource("tests/fixtures/audio/chunks/chunk_short.wav")

    # Create recorder
    recorder = ContinuousRecorder(
        tcp_server=mock_tcp_server,
        output_dir="output",
        filename_prefix="test",
        audio_source=audio_source
    )

    # Start recording
    recorder.start()

    # Verify events were emitted
    assert "server_ready" in events
    assert "recording_started" in events
    assert "chunk_ready" in events
    assert "recording_stopped" in events
```

## Creating Test Audio Files

To create custom test audio files for specific scenarios:

### Silence Testing
```bash
# Generate 5 seconds of silence
sox -n -r 16000 -c 1 tests/fixtures/silence_5s.wav trim 0 5
```

### Speech + Silence Pattern
```bash
# Record speech, add silence, concatenate
sox recording.wav -p pad 0 2 | sox - tests/fixtures/speech_with_pause.wav
```

### Varying Noise Floors
```bash
# Add white noise at different levels
sox input.wav -p synth whitenoise vol 0.001 | sox - output_quiet.wav
sox input.wav -p synth whitenoise vol 0.01 | sox - output_noisy.wav
```

## Benefits

1. **Reproducible** - Same audio file produces same results every time
2. **Fast** - No real-time constraints, tests run at full speed
3. **Comprehensive** - Can test edge cases (perfect silence, very quiet, very loud)
4. **No hardware** - Doesn't require microphone access
5. **CI-friendly** - Works in headless environments

## Limitations

- Doesn't test actual microphone capture (sounddevice I/O)
- Doesn't test real-time latency or buffer underruns
- Doesn't test hardware-specific issues (sample rate mismatches, etc.)

For testing actual microphone integration, use the live integration tests (`make test-live`).
