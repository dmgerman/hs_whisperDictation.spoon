# Whisper Stream - TCP-based Continuous Audio Recording

**Author:** WhisperDictation Development
**Date:** 2026-02-16 (Updated)

## Overview

### What is whisper_stream.py?

`whisper_stream.py` is a Python-based continuous audio recording server that uses Silero VAD (Voice Activity Detection) to intelligently chunk audio in real-time. Unlike simple recording tools, it:

- Records continuously from the microphone
- Detects silence boundaries using AI-powered VAD
- Creates chunks automatically when detecting pauses
- Sends real-time events over TCP sockets
- Accepts commands for recording control
- Persistent server pattern (stays running across recordings)
- Saves both individual chunks and complete recordings

### Why TCP Sockets?

We use TCP sockets instead of subprocess pipes (stdin/stdout) because:

1. **No buffering issues** - Events arrive in real-time, not delayed until process exit
2. **2-way communication** - Client can send commands to server (start/stop recording, shutdown)
3. **Event loop friendly** - Non-blocking callbacks work with async event loops
4. **Language agnostic** - Any language with socket support can use it
5. **Reliable delivery** - TCP guarantees message order and delivery
6. **Persistent server** - Server stays running across multiple recording sessions

### Use Cases

#### Integration with Hammerspoon (Primary)
Used by WhisperDictation spoon via `StreamingRecorder`:
- Persistent server (start once, reuse for multiple recordings)
- Real-time chunk emission during recording
- Clean shutdown via `cleanup()` when spoon unloads
- Controlled via `start_recording`, `stop_recording`, `shutdown` commands

#### Standalone Transcription Tool
Run from command line to record and chunk audio for later transcription:
```bash
python3 whisper_stream.py \
  --tcp-port 12341 \
  --output-dir ./recordings \
  --filename-prefix session \
  --silence-threshold 2.0
```

#### Custom Transcription Pipelines
Use as a front-end for transcription systems:
- Receive chunks in real-time
- Send each chunk to transcription API
- Display results as user speaks
- Save complete recording for auditing

## Quick Start

### Installation

Requirements:
```bash
pip install sounddevice scipy torch onnxruntime
```

### Running the Server

```bash
python3 whisper_stream.py \
  --tcp-port 12341 \
  --output-dir /tmp/recordings \
  --filename-prefix test \
  --silence-threshold 2.0 \
  --min-chunk-duration 3.0 \
  --max-chunk-duration 600.0
```

The server will:
1. Start TCP server on port 12341
2. Print: `{"status": "listening", "port": 12341}` to stderr
3. Wait for a client to connect
4. Wait for `start_recording` command
5. Stay running across multiple recording sessions

### Minimal Client Example (Python)

```python
import socket
import json
import sys

# Connect to server
client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
client.connect(('127.0.0.1', 12341))

print("Connected! Server ready...", file=sys.stderr)

# Start recording
start_cmd = json.dumps({"command": "start_recording"}) + "\n"
client.send(start_cmd.encode('utf-8'))

# Receive events
buffer = ""
while True:
    data = client.recv(1024).decode('utf-8')
    if not data:
        break

    buffer += data
    while '\n' in buffer:
        line, buffer = buffer.split('\n', 1)
        event = json.loads(line)

        if event['type'] == 'chunk_ready':
            print(f"Chunk {event['chunk_num']}: {event['audio_file']}")
        elif event['type'] == 'recording_stopped':
            print("Recording finished!")
            break

# Send stop command
stop_cmd = json.dumps({"command": "stop_recording"}) + "\n"
client.send(stop_cmd.encode('utf-8'))

# Wait for final events, then shutdown server
import time
time.sleep(1)
shutdown_cmd = json.dumps({"command": "shutdown"}) + "\n"
client.send(shutdown_cmd.encode('utf-8'))

client.close()
```

## Protocol Specification

### Message Format

All messages are **newline-delimited JSON** (one JSON object per line).

#### From Server to Client (Events)
```
{"type": "event_name", "param1": "value1", ...}\n
```

#### From Client to Server (Commands)
```
{"command": "command_name", "param1": "value1", ...}\n
```

### Event Types

#### server_ready
Sent when server is ready to receive commands (after client connects).

```json
{"type": "server_ready"}
```

#### recording_started
Sent when recording begins (after `start_recording` command).

```json
{"type": "recording_started"}
```

#### chunk_ready
Sent when a new audio chunk is saved to disk.

```json
{
  "type": "chunk_ready",
  "chunk_num": 1,
  "audio_file": "/tmp/recordings/test_chunk_001.wav",
  "is_final": false
}
```

**Parameters:**
- `chunk_num` (int): Sequential chunk number (starts at 1)
- `audio_file` (string): Absolute path to WAV file
- `is_final` (boolean): True for last chunk when recording stops

#### complete_file
Sent after recording stops, with path to complete recording file.

```json
{
  "type": "complete_file",
  "file_path": "/tmp/recordings/test-20260214-183520.wav"
}
```

**Parameters:**
- `file_path` (string): Absolute path to complete WAV file (timestamped)

#### silence_warning
Sent when microphone is detected as off (perfect silence for configured duration).

```json
{
  "type": "silence_warning",
  "message": "Microphone off - stopping recording"
}
```

**Parameters:**
- `message` (string): Human-readable warning message

#### recording_stopped
Sent when recording ends (either by command or mic detection).

```json
{"type": "recording_stopped"}
```

#### error
Sent when an error occurs. Server stays running (resilient to transient errors).

```json
{
  "type": "error",
  "error": "Error message here"
}
```

**Parameters:**
- `error` (string): Error description

### Command Types

#### start_recording
Start a new recording session.

```json
{"command": "start_recording"}
```

Server will:
1. Check if already recording (send error if yes)
2. Start audio capture loop
3. Send `recording_started` event
4. Begin chunking audio

#### stop_recording
Stop the current recording session.

```json
{"command": "stop_recording"}
```

Server will:
1. Stop recording loop
2. Save complete recording file
3. Send `complete_file` event
4. Save final chunk (if any audio buffered)
5. Send `chunk_ready` for final chunk (with `is_final=true`)
6. Send `recording_stopped` event
7. **Stay running** for next recording session

#### shutdown
Gracefully shutdown the server (called when spoon unloads).

```json
{"command": "shutdown"}
```

Server will:
1. Stop any active recording
2. Send final events
3. Close TCP connection
4. Exit process

#### disconnect
Client disconnecting (same as shutdown but saves any in-progress recording first).

```json
{"command": "disconnect"}
```

### Configuration Parameters

Command-line arguments:

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `--check-deps` | flag | - | Check dependencies and exit |
| `--tcp-port` | int | 12341 | TCP server port |
| `--output-dir` | path | **required** | Directory for audio files |
| `--filename-prefix` | string | **required** | Prefix for chunk filenames |
| `--silence-threshold` | float | 2.0 | Seconds of silence to trigger new chunk |
| `--min-chunk-duration` | float | 3.0 | Minimum chunk length (seconds) |
| `--max-chunk-duration` | float | 600.0 | Maximum chunk length (seconds) |
| `--test-file` | path | - | WAV file to use instead of microphone (for testing) |
| `--audio-input` | string | - | Audio input device name (e.g., 'BlackHole 2ch') |
| `--perfect-silence-duration` | float | 0.0 | Duration of perfect silence to detect mic off (0=disabled, 2.0 for testing) |

**Notes:**
- `--test-file`: Enables file input mode for deterministic testing with pre-recorded audio
- `--audio-input`: Specify audio device by name (useful for routing via BlackHole)
- `--perfect-silence-duration`: Default 0 (disabled) to avoid false positives. Enable for testing mic detection.

## Communication Flows

### Startup Sequence

```
Client                           Server
  |                                 |
  |                                 | Start TCP server
  |                                 | Print {"status": "listening", ...} to stderr
  |                                 | wait_for_client() [blocking, 60s timeout]
  |                                 |
  |---- TCP connect --------------->|
  |                                 |
  |<--- server_ready ---------------|
  |                                 | Wait for commands...
```

### Recording Flow (Persistent Server Pattern)

```
Client                           Server
  |                                 |
  |---- start_recording ----------->|
  |                                 |
  |<--- recording_started ----------|
  |                                 | Start audio capture
  |                                 |
  |                                 | [Audio callback every 0.5s]
  |                                 | Buffer audio...
  |                                 | Check VAD for voice activity
  |                                 |
  |                                 | [After 2s silence detected]
  |                                 | Save chunk to disk
  |<--- chunk_ready ----------------|
  |                                 |
  | Process chunk (transcribe)      |
  |                                 | Continue recording...
  |                                 |
  |---- stop_recording ------------>|
  |                                 |
  |                                 | Save complete recording
  |<--- complete_file --------------|
  |                                 | Save final chunk
  |<--- chunk_ready (is_final) -----|
  |<--- recording_stopped ----------|
  |                                 |
  |                                 | [Server stays running]
  |                                 | Wait for next command...
  |                                 |
  |---- start_recording ----------->| [Second recording session]
  |<--- recording_started ----------|
  |                                 | ...
```

### Shutdown Flow (Clean)

```
Client                           Server
  |                                 |
  |---- shutdown ------------------->|
  |                                 |
  |                                 | Stop recording if active
  |                                 | Close TCP connection
  |                                 | Exit process
  |                                 |
  X                                 X
```

### Error Recovery Flow

```
Client                           Server
  |                                 |
  |---- start_recording ----------->|
  |<--- recording_started ----------|
  |                                 |
  |                                 | [Microphone error occurs]
  |<--- error ----------------------|
  |                                 |
  |                                 | [Server stays running]
  |                                 | Wait for next command...
  |                                 |
  |---- start_recording ----------->| [Retry]
  |<--- recording_started ----------|
```

## Architecture

### Persistent Server Pattern

**Key Design Decision:** Server stays running across multiple recording sessions.

**Benefits:**
- Reduces startup latency (no model reload)
- Maintains TCP connection
- Better for real-time applications
- Simpler state management

**Lifecycle:**
1. **Startup:** Server starts, loads VAD model, opens TCP port
2. **Connect:** Client connects, receives `server_ready`
3. **Record:** Multiple `start_recording` → `stop_recording` cycles
4. **Shutdown:** Client sends `shutdown` command (only on spoon unload)

### Components

#### TCPServer
- Handles TCP connection
- Sends JSON events to client
- Receives JSON commands from client
- Newline-delimited message framing

#### ContinuousRecorder
- Records audio continuously
- Uses Silero VAD for silence detection
- Creates chunks based on silence/duration
- Handles microphone errors gracefully
- Stays running after errors (resilient)

#### FileAudioSource (Test Mode)
- Replaces microphone with file input
- Enables deterministic testing
- Simulates real-time streaming

### Error Handling

**Microphone Failures:**
- Server catches exceptions in audio callback
- Sends `error` event to client
- **Stays running** (doesn't crash)
- Client can retry with new `start_recording` command

**Connection Loss:**
- Saves any in-progress recording
- Waits for reconnection (60s timeout)
- Exits if no reconnection

## Testing

### Unit Tests (pytest)

Located in `tests/python/`:
- `test_audio_processing.py` - Audio normalization, silence detection
- `test_tcp_server.py` - TCP communication
- `test_continuous_recorder.py` - VAD, chunking, lifecycle
- `test_file_integration.py` - File input mode

Run:
```bash
pytest tests/python/
```

### Integration Tests (Shell)

Located in `tests/`:
- `test_streaming_recorder_integration.sh` - Full integration with Hammerspoon
- `test_streaming_simple.sh` - Quick smoke test

Run:
```bash
./tests/test_streaming_recorder_integration.sh
```

### File Input Testing

Use `--test-file` for deterministic testing:

```bash
python3 whisper_stream.py \
  --tcp-port 12341 \
  --output-dir /tmp/test \
  --filename-prefix test \
  --test-file tests/fixtures/audio/complete/en-20260214-200536.wav
```

**Benefits:**
- No microphone required
- Reproducible results
- Faster than real-time (no recording delays)
- Ideal for CI/CD pipelines

### BlackHole Virtual Audio Testing

Use BlackHole for live testing with fixture audio:

```bash
# Install BlackHole
brew install blackhole-2ch

# Run server with BlackHole
python3 whisper_stream.py \
  --audio-input "BlackHole 2ch" \
  ...

# Play fixture audio (becomes "microphone" input)
afplay -d "BlackHole 2ch" tests/fixtures/audio/complete/en-20260214-200536.wav
```

## Troubleshooting

### "Address already in use"
- Another server instance is running on the same port
- Solution: Kill process or use different `--tcp-port`

### "No audio devices found"
- Microphone not available or permissions denied
- Solution: Grant microphone access, check device availability

### Server exits immediately
- Missing required arguments (`--output-dir`, `--filename-prefix`)
- Use `--check-deps` to verify dependencies

### Chunks not being created
- Audio input too quiet (below VAD threshold)
- Silence threshold too high
- Solution: Check input levels, adjust `--silence-threshold`

### Perfect silence warning on startup
- `--perfect-silence-duration` enabled but microphone is silent
- Solution: Disable (default 0.0) or check microphone is working

## Dependencies

- **sounddevice** - Audio capture
- **scipy** - Audio processing, WAV file I/O
- **torch** - Silero VAD model inference
- **onnxruntime** - Alternative VAD runtime (optional)

Check dependencies:
```bash
python3 whisper_stream.py --check-deps
```

## Performance

**VAD Model:**
- Silero VAD (lightweight, accurate)
- CPU inference (fast enough for real-time)
- ~10ms latency per audio chunk

**Memory:**
- ~200MB baseline (model + buffers)
- ~1MB per minute of recording (in-memory buffer)

**CPU:**
- ~5-10% on modern CPUs
- Scales with audio processing frequency

## Future Enhancements

- Multiple audio input sources
- Configurable VAD model
- WebSocket support
- Streaming transcription integration
- Audio format options (MP3, FLAC)

---

**For integration with Hammerspoon, see:** `recorders/streaming/streaming_recorder.lua`
**For testing documentation, see:** `docs/testing.md`
