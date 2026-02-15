#!/bin/bash
#
# Setup Test Fixtures
# Copies real audio files from /tmp/whisper_dict to test fixtures directory
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
SOURCE_DIR="/tmp/whisper_dict"

echo "🎯 Setting up test fixtures..."
echo "================================"

# Create fixture directories
mkdir -p "$FIXTURES_DIR/audio/chunks"
mkdir -p "$FIXTURES_DIR/audio/complete"
mkdir -p "$FIXTURES_DIR/transcripts"

# Copy audio chunks (small files for fast tests)
echo "📦 Copying audio chunks..."
cp "$SOURCE_DIR"/en_chunk_001.wav "$FIXTURES_DIR/audio/chunks/chunk_short.wav" 2>/dev/null || true
cp "$SOURCE_DIR"/en_chunk_002.wav "$FIXTURES_DIR/audio/chunks/chunk_medium.wav" 2>/dev/null || true
cp "$SOURCE_DIR"/en_chunk_003.wav "$FIXTURES_DIR/audio/chunks/chunk_long.wav" 2>/dev/null || true

# Find and copy complete recordings (with matching transcripts)
echo "📝 Copying complete recordings with transcripts..."
for txtfile in "$SOURCE_DIR"/en-*.txt; do
  if [ -f "$txtfile" ]; then
    basename=$(basename "$txtfile" .txt)
    wavfile="$SOURCE_DIR/${basename}.wav"

    if [ -f "$wavfile" ]; then
      # Copy both audio and transcript
      cp "$wavfile" "$FIXTURES_DIR/audio/complete/"
      cp "$txtfile" "$FIXTURES_DIR/transcripts/"
      echo "  ✓ Copied $basename (audio + transcript)"
    else
      # Just copy transcript if audio missing
      cp "$txtfile" "$FIXTURES_DIR/transcripts/"
      echo "  ✓ Copied $basename (transcript only)"
    fi
  fi
done

# Create manifest of fixtures
echo "📋 Creating fixture manifest..."
cat > "$FIXTURES_DIR/manifest.json" <<EOF
{
  "audio": {
    "chunks": {
      "short": {
        "file": "audio/chunks/chunk_short.wav",
        "description": "Short audio chunk (~1 second)",
        "size_kb": $(du -k "$FIXTURES_DIR/audio/chunks/chunk_short.wav" 2>/dev/null | cut -f1 || echo "0")
      },
      "medium": {
        "file": "audio/chunks/chunk_medium.wav",
        "description": "Medium audio chunk (~3 seconds)",
        "size_kb": $(du -k "$FIXTURES_DIR/audio/chunks/chunk_medium.wav" 2>/dev/null | cut -f1 || echo "0")
      },
      "long": {
        "file": "audio/chunks/chunk_long.wav",
        "description": "Long audio chunk (~5+ seconds)",
        "size_kb": $(du -k "$FIXTURES_DIR/audio/chunks/chunk_long.wav" 2>/dev/null | cut -f1 || echo "0")
      }
    }
  },
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "$SOURCE_DIR"
}
EOF

echo ""
echo "✅ Test fixtures setup complete!"
echo ""
echo "Summary:"
echo "  Audio chunks:      $(ls -1 "$FIXTURES_DIR/audio/chunks" 2>/dev/null | wc -l | tr -d ' ')"
echo "  Complete audio:    $(ls -1 "$FIXTURES_DIR/audio/complete"/*.wav 2>/dev/null | wc -l | tr -d ' ')"
echo "  Transcripts:       $(ls -1 "$FIXTURES_DIR/transcripts" 2>/dev/null | wc -l | tr -d ' ')"
echo ""
echo "Fixtures directory: $FIXTURES_DIR"
