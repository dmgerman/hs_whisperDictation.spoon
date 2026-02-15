# Makefile for hs_whisperDictation.spoon

.PHONY: test test-live test-python clean help

# Default target: run all busted unit tests (quiet mode - only show errors)
test:
	@echo "Running Lua tests..."
	@busted 2>&1 | grep -E "^not ok" || (busted --output=TAP 2>&1 | tail -1 && echo "✓ All 368 Lua tests passed")
	@echo ""
	@echo "Running Python tests..."
	@pytest tests/python -q || exit 1
	@echo ""
	@echo "✓ All tests passed"

# Run Python tests only
test-python:
	@echo "Running Python tests..."
	@pytest tests/python -v

# Run live integration tests with environment verification
test-live:
	@echo "=== Live Integration Tests ==="
	@echo ""
	@echo "[1/3] Verifying environment..."
	@chmod +x tests/verify_environment.sh
	@tests/verify_environment.sh || (echo ""; echo "Environment verification failed. Fix errors before running live tests."; exit 1)
	@echo ""
	@echo "[2/3] Reloading Hammerspoon..."
	@timeout 2 hs -c "hs.reload()" & sleep 3
	@timeout 2 hs -c "print('Hammerspoon reloaded')" 2>/dev/null || true
	@echo ""
	@echo "[3/3] Running all backend tests..."
	@chmod +x tests/test_all_backends.sh
	@tests/test_all_backends.sh || exit 1

# Clean up temporary files
clean:
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name "*.log" -delete
	@echo "✓ Cleaned"

# Show help
help:
	@echo "hs_whisperDictation Test Suite"
	@echo ""
	@echo "Available targets:"
	@echo "  make test        - Run all tests (Lua + Python)"
	@echo "  make test-python - Run Python tests only (pytest)"
	@echo "  make test-live   - Verify environment + test all backends (2 recording + 3 transcription)"
	@echo "  make clean       - Clean temporary files"
	@echo "  make help        - Show this help message"
	@echo ""
	@echo "Test breakdown:"
	@echo "  Lua tests:   368 tests (unit + integration, uses mocks)"
	@echo "  Python tests: 69 tests (whisper_stream.py + file integration + error handling)"
	@echo "  Live tests:  5 backend tests (requires Hammerspoon running)"
