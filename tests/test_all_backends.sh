#!/bin/bash
# Master Test Suite - All Recording and Transcription Backends
# Runs all backend tests in sequence

set -e
cd "$(dirname "$0")/.."

TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0

echo "========================================="
echo "Master Test Suite: All Backends"
echo "========================================="
echo ""

# Track results
declare -A RESULTS

run_test() {
    local name="$1"
    local script="$2"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ -f "$script" ]; then
        chmod +x "$script"
        if "$script"; then
            RESULTS["$name"]="PASS"
            echo ""
            echo "✓ $name PASSED"
        else
            RESULTS["$name"]="FAIL"
            echo ""
            echo "✗ $name FAILED"
        fi
    else
        RESULTS["$name"]="SKIP"
        echo "⊘ Test script not found: $script"
    fi
    echo ""
}

# Run all tests
run_test "Sox Recording Backend" "tests/test_sox_integration.sh"
run_test "Pythonstream Recording Backend" "tests/test_pythonstream_integration.sh"
run_test "Transcription: WhisperKit" "tests/test_transcription_whisperkit.sh"
run_test "Transcription: Whisper CLI" "tests/test_transcription_whispercli.sh"
run_test "Transcription: Whisper Server" "tests/test_transcription_whisperserver.sh"

# Summary
echo "========================================="
echo "Test Suite Summary"
echo "========================================="
echo ""

for test_name in "${!RESULTS[@]}"; do
    result="${RESULTS[$test_name]}"
    case "$result" in
        PASS)
            echo "✓ $test_name"
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
            ;;
        FAIL)
            echo "✗ $test_name"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            ;;
        SKIP)
            echo "⊘ $test_name (skipped)"
            ;;
    esac
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
done

echo ""
echo "Total: $TOTAL_TESTS tests"
echo "Passed: $TOTAL_PASSED"
echo "Failed: $TOTAL_FAILED"
echo ""

if [ $TOTAL_FAILED -eq 0 ]; then
    echo "✅ All backend tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
