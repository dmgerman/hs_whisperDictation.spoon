#!/bin/bash
# Example: Test whisper_stream.py with a pre-recorded audio file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPOON_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
AUDIO_FILE="${1:-$SPOON_DIR/tests/fixtures/audio/chunks/chunk_short.wav}"
OUTPUT_DIR="${2:-/tmp/whisper_test_output}"
TCP_PORT=12399

echo "Testing whisper_stream.py with file input mode"
echo "================================================"
echo "Audio file: $AUDIO_FILE"
echo "Output dir: $OUTPUT_DIR"
echo "TCP port:   $TCP_PORT"
echo ""

# Check if audio file exists
if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: Audio file not found: $AUDIO_FILE"
    echo "Usage: $0 [audio_file.wav] [output_dir]"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Start whisper_stream.py with test file
echo "Starting whisper_stream.py in test mode..."
python3 "$SPOON_DIR/whisper_stream.py" \
    --test-file "$AUDIO_FILE" \
    --output-dir "$OUTPUT_DIR" \
    --filename-prefix "test" \
    --tcp-port "$TCP_PORT" \
    --silence-threshold 1.0 \
    --min-chunk-duration 0.5 \
    --max-chunk-duration 30.0 &

WHISPER_PID=$!
echo "Started whisper_stream.py (PID: $WHISPER_PID)"

# Give it a moment to start
sleep 1

# Simple TCP client to send commands
echo ""
echo "Sending commands via TCP..."
{
    sleep 0.5
    echo '{"command":"start_recording"}'
    sleep 2
    echo '{"command":"stop_recording"}'
    sleep 0.5
    echo '{"command":"shutdown"}'
} | nc localhost "$TCP_PORT" &

# Wait for whisper_stream to finish
wait $WHISPER_PID 2>/dev/null || true

echo ""
echo "Test complete!"
echo ""
echo "Output files:"
ls -lh "$OUTPUT_DIR"/*.wav 2>/dev/null || echo "No WAV files created"

echo ""
echo "To test with your own audio file:"
echo "  $0 /path/to/your/audio.wav"
