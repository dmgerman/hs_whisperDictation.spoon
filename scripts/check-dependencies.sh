#!/bin/bash
# Check all dependencies for hs_whisperDictation.spoon
#
# Usage:
#   ./scripts/check-dependencies.sh [python-path]
#
# If python-path is omitted, uses python3 from PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPOON_DIR="$(dirname "$SCRIPT_DIR")"
WHISPER_STREAM="$SPOON_DIR/recorders/streaming/whisper_stream.py"

PYTHON="${1:-python3}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass=0
fail=0
warn=0

ok()   { echo -e "  ${GREEN}OK${NC}   $1"; pass=$((pass + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; fail=$((fail + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC} $1"; warn=$((warn + 1)); }

echo "=== hs_whisperDictation dependency check ==="
echo ""

# --- Python ---
echo "Python:"
if command -v "$PYTHON" &>/dev/null; then
  PYTHON_FULL="$(command -v "$PYTHON")"
  PYTHON_VER="$("$PYTHON_FULL" --version 2>&1)"
  ok "$PYTHON_VER ($PYTHON_FULL)"
else
  fail "Python not found: $PYTHON"
  echo ""
  echo "Cannot continue without Python. Install it or pass the correct path."
  exit 1
fi

# --- Python packages (via --check-deps) ---
echo ""
echo "Python packages (streaming recorder):"
if [ -f "$WHISPER_STREAM" ]; then
  DEPS_OUTPUT="$("$PYTHON_FULL" "$WHISPER_STREAM" --check-deps 2>&1)" || true
  if echo "$DEPS_OUTPUT" | grep -q '"status": "ok"' 2>/dev/null || echo "$DEPS_OUTPUT" | grep -q '"status":"ok"' 2>/dev/null; then
    ok "All Python packages installed"
  else
    fail "Missing packages"
    # Parse and show individual missing packages
    echo "$DEPS_OUTPUT" | "$PYTHON_FULL" -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for pkg in data.get('missing', []):
        print('       -', pkg)
except:
    print('       Could not parse output:', sys.stdin.read())
" 2>/dev/null || echo "       Raw output: $DEPS_OUTPUT"
    echo ""
    echo "  Install with:"
    echo "    $PYTHON_FULL -m pip install numpy sounddevice scipy torch torchaudio"
  fi
else
  fail "whisper_stream.py not found at $WHISPER_STREAM"
fi

# --- sox ---
echo ""
echo "Recording backends:"
if command -v sox &>/dev/null; then
  SOX_VER="$(sox --version 2>&1 | head -1)"
  ok "sox: $SOX_VER"
else
  skip "sox not installed (optional, needed for sox recorder)"
fi

# --- Transcription backends ---
echo ""
echo "Transcription backends (at least one required):"
found_transcriber=false

if command -v whisperkit-cli &>/dev/null; then
  ok "whisperkit-cli found"
  found_transcriber=true
else
  skip "whisperkit-cli not installed (brew install whisperkit-cli)"
fi

if command -v whisper-cli &>/dev/null; then
  ok "whisper-cli found"
  found_transcriber=true
else
  skip "whisper-cli not installed (build from whisper.cpp)"
fi

# Check for whisper server on default port
if curl -s --connect-timeout 2 "http://localhost:8080/health" &>/dev/null; then
  ok "whisper server responding on localhost:8080"
  found_transcriber=true
else
  skip "whisper server not running on localhost:8080"
fi

if [ "$found_transcriber" = false ]; then
  fail "No transcription backend found"
fi

# --- Hammerspoon ---
echo ""
echo "Hammerspoon:"
if command -v hs &>/dev/null; then
  if timeout 3 hs -c "print('ok')" &>/dev/null; then
    ok "Hammerspoon IPC responding"
  else
    skip "Hammerspoon installed but IPC not responding"
  fi
else
  skip "hs CLI not in PATH"
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
echo -e "  ${GREEN}$pass passed${NC}, ${RED}$fail failed${NC}, ${YELLOW}$warn skipped${NC}"

if [ $fail -gt 0 ]; then
  echo ""
  echo "Fix the failures above before using the spoon."
  exit 1
fi

exit 0
