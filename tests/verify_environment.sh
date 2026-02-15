#!/bin/bash
# Environment Verification Test
# Checks all dependencies and configuration for hs_whisperDictation

set -e

ERRORS=0

echo "=== Environment Verification for hs_whisperDictation ==="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

# =============================================================================
# Test 1: Hammerspoon
# =============================================================================
echo "Test 1: Hammerspoon"
if command -v hs >/dev/null 2>&1; then
    pass "Hammerspoon CLI installed"

    # Check if Hammerspoon is running
    if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
        pass "Hammerspoon is running"

        # Test IPC communication
        if timeout 2 hs -c "print('test')" >/dev/null 2>&1; then
            pass "Hammerspoon IPC working"
        else
            fail "Hammerspoon IPC not responding"
        fi
    else
        fail "Hammerspoon is not running"
    fi
else
    fail "Hammerspoon CLI (hs) not found in PATH"
fi
echo ""

# =============================================================================
# Test 2: Spoon Installation
# =============================================================================
echo "Test 2: Spoon Installation"
if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
    SPOON_LOADED=$(timeout 2 hs -c "print(spoon.hs_whisperDictation ~= nil)" 2>/dev/null || echo "false")
    if [ "$SPOON_LOADED" = "true" ]; then
        pass "hs_whisperDictation spoon is loaded"

        # Get version
        VERSION=$(timeout 2 hs -c "print(spoon.hs_whisperDictation.version)" 2>/dev/null || echo "unknown")
        echo "  Version: $VERSION"

        # Get current backend
        BACKEND=$(timeout 2 hs -c "print(spoon.hs_whisperDictation.recordingBackend)" 2>/dev/null || echo "unknown")
        echo "  Recording backend: $BACKEND"

        # Get current method
        METHOD=$(timeout 2 hs -c "print(spoon.hs_whisperDictation.transcriptionMethod)" 2>/dev/null || echo "unknown")
        echo "  Transcription method: $METHOD"
    else
        fail "hs_whisperDictation spoon is not loaded"
        echo "  Add to init.lua: hs.loadSpoon('hs_whisperDictation')"
    fi
else
    warn "Cannot check spoon (Hammerspoon not running)"
fi
echo ""

# =============================================================================
# Test 3: Busted Testing Framework
# =============================================================================
echo "Test 3: Busted Testing Framework"
if command -v busted >/dev/null 2>&1; then
    VERSION=$(busted --version 2>&1 | head -1)
    pass "Busted is installed: $VERSION"
else
    fail "Busted not found (install: luarocks install busted)"
fi
echo ""

# =============================================================================
# Test 4: Sox Backend Dependencies
# =============================================================================
echo "Test 4: Sox Backend Dependencies"
if command -v sox >/dev/null 2>&1; then
    VERSION=$(sox --version 2>&1 | head -1)
    pass "Sox is installed: $VERSION"
else
    warn "Sox not found (install: brew install sox)"
    echo "  Sox backend will not work without it"
fi
echo ""

# =============================================================================
# Test 5: Python Backend Dependencies
# =============================================================================
echo "Test 5: Python Backend Dependencies"

# Get configured recording backend
if pgrep -x "Hammerspoon" >/dev/null 2>&1 && [ "$SPOON_LOADED" = "true" ]; then
    BACKEND=$(timeout 2 hs -c "print(spoon.hs_whisperDictation.recordingBackend)" 2>/dev/null | grep -v "profile:" | grep -v "streamDeck" | head -1 || echo "unknown")
else
    BACKEND="unknown"
fi

echo "  Configured backend: $BACKEND"

# Only check Python if using pythonstream backend
if [ "$BACKEND" = "pythonstream" ]; then
    # Check if spoon is loaded to get Python path
    PYTHON_CMD=$(timeout 2 hs -c "local cmd = 'python3'; if spoon.hs_whisperDictation.pythonstreamConfig and spoon.hs_whisperDictation.pythonstreamConfig.pythonCmd then cmd = spoon.hs_whisperDictation.pythonstreamConfig.pythonCmd end; print(cmd)" 2>/dev/null)
    # Fallback if we got nil or empty
    if [ -z "$PYTHON_CMD" ] || [ "$PYTHON_CMD" = "nil" ]; then
        PYTHON_CMD="python3"
    fi

    if command -v "$PYTHON_CMD" >/dev/null 2>&1; then
        VERSION=$($PYTHON_CMD --version 2>&1)
        pass "Python is installed: $VERSION"

        # Check Python packages - these are REQUIRED for pythonstream
        if $PYTHON_CMD -c "import sounddevice" 2>/dev/null; then
            pass "  sounddevice package installed"
        else
            fail "  sounddevice not installed (required: pip install sounddevice)"
        fi

        if $PYTHON_CMD -c "import scipy" 2>/dev/null; then
            pass "  scipy package installed"
        else
            fail "  scipy not installed (required: pip install scipy)"
        fi

        if $PYTHON_CMD -c "import torch" 2>/dev/null; then
            pass "  torch package installed"
        else
            fail "  torch not installed (required: pip install torch)"
        fi
    else
        fail "Python ($PYTHON_CMD) not found (required for pythonstream backend)"
    fi
else
    pass "Python check skipped (not using pythonstream backend)"
fi
echo ""

# =============================================================================
# Test 6: Transcription Method Dependencies
# =============================================================================
echo "Test 6: Transcription Method Dependencies"

# Get configured transcription method
if pgrep -x "Hammerspoon" >/dev/null 2>&1 && [ "$SPOON_LOADED" = "true" ]; then
    METHOD=$(timeout 2 hs -c "print(spoon.hs_whisperDictation.transcriptionMethod)" 2>/dev/null | grep -v "profile:" | grep -v "streamDeck" | head -1 || echo "unknown")
else
    METHOD="unknown"
fi

echo "  Configured method: $METHOD"

# Check based on configured method
case "$METHOD" in
    whisperkitcli)
        if command -v whisperkit-cli >/dev/null 2>&1; then
            pass "whisperkit-cli found in PATH"
        else
            fail "whisperkit-cli not found (required for whisperkitcli method)"
        fi
        ;;
    whispercli)
        if command -v whisper >/dev/null 2>&1; then
            pass "whisper CLI found"
        else
            fail "whisper CLI not found (required for whispercli method)"
        fi
        ;;
    whisperserver)
        if command -v curl >/dev/null 2>&1; then
            pass "curl installed"
        else
            fail "curl not found (required for whisperserver method)"
        fi

        # Check if server is running
        if curl -s --max-time 2 http://localhost:9090/status >/dev/null 2>&1; then
            pass "Whisper server running on localhost:9090"
        elif curl -s --max-time 2 http://127.0.0.1:9090/status >/dev/null 2>&1; then
            pass "Whisper server running on 127.0.0.1:9090"
        else
            # Server not running - this is an error since whisperserver method is configured
            fail "Whisper server not running on localhost:9090"
            echo "  The server should be started automatically by Hammerspoon"
            echo "  Check Hammerspoon console for server startup errors"
            echo "  Or start manually: whisper-server --port 9090"
        fi
        ;;
    groq)
        if command -v curl >/dev/null 2>&1; then
            pass "curl installed"
        else
            fail "curl not found (required for groq method)"
        fi
        # Note: API key check would require reading config
        ;;
    *)
        pass "Transcription method check skipped (method: $METHOD)"
        ;;
esac
echo ""

# =============================================================================
# Test 7: File System Permissions
# =============================================================================
echo "Test 7: File System Permissions"

# Check temp directory
TEMP_DIR="/tmp/whisper_dict"
if [ -d "$TEMP_DIR" ]; then
    pass "Temp directory exists: $TEMP_DIR"
    if [ -w "$TEMP_DIR" ]; then
        pass "Temp directory is writable"
    else
        fail "Temp directory not writable: $TEMP_DIR"
    fi
else
    if mkdir -p "$TEMP_DIR" 2>/dev/null; then
        pass "Created temp directory: $TEMP_DIR"
    else
        fail "Cannot create temp directory: $TEMP_DIR"
    fi
fi
echo ""

# =============================================================================
# Test 8: Microphone Access
# =============================================================================
echo "Test 8: Microphone Access"
# Note: Cannot programmatically verify on macOS
# If tests fail due to mic issues, check: System Settings → Privacy & Security → Microphone
pass "Microphone access check skipped (verify manually if recording fails)"
echo ""

# =============================================================================
# Test 9: Required Lua Modules (for tests)
# =============================================================================
echo "Test 9: Test Infrastructure"
if [ -f "tests/helpers/mock_hs.lua" ]; then
    pass "Mock Hammerspoon APIs available"
else
    fail "tests/helpers/mock_hs.lua not found"
fi

if [ -f "tests/helpers/async_helper.lua" ]; then
    pass "Async test helper available"
else
    fail "tests/helpers/async_helper.lua not found"
fi

if [ -f ".busted" ]; then
    pass "Busted configuration file present"
else
    warn ".busted configuration not found"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "========================================="
echo "Summary:"
echo "  Errors: $ERRORS"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Environment is ready${NC}"
    exit 0
else
    echo -e "${RED}✗ Environment has $ERRORS errors${NC}"
    echo "  Fix errors before running tests"
    exit 1
fi
