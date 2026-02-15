"""
Test microphone failure handling.
"""
import pytest
import subprocess
import json
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))


def test_microphone_not_available():
    """Should exit with error code 1 when microphone is not available."""
    # Try to run whisper_stream.py with microphone (will fail if no mic)
    # Use a mock that forces sounddevice to fail

    test_script = """
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Mock sounddevice to always fail
class MockSD:
    class InputStream:
        def __init__(self, *args, **kwargs):
            raise RuntimeError("No default input device found")
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass

import sys
sys.modules['sounddevice'] = MockSD()

# Now run main
from whisper_stream import main
import argparse

# Override sys.argv
sys.argv = [
    'whisper_stream.py',
    '--output-dir', '/tmp/test_mic_fail',
    '--filename-prefix', 'test',
    '--tcp-port', '12399'
]

# This should fail because microphone is not available
try:
    main()
    print("SHOULD_HAVE_FAILED", file=sys.stderr)
    sys.exit(99)  # Should not reach here
except SystemExit as e:
    # Capture the exit code
    sys.exit(e.code)
"""

    result = subprocess.run(
        ['python3', '-c', test_script],
        capture_output=True,
        cwd=str(Path(__file__).parent.parent.parent),
        timeout=5
    )

    # Should exit with error code (not 0)
    # Currently it exits with 0, which is wrong
    print(f"Exit code: {result.returncode}")
    print(f"Stderr: {result.stderr.decode()}")

    # This test will FAIL with current implementation
    # because the error is swallowed and it exits with 0
    if result.returncode == 0:
        pytest.fail(
            "whisper_stream.py exited with code 0 when microphone failed. "
            "Should exit with code 1 to indicate failure."
        )


def test_microphone_failure_sends_error_event():
    """Should send error event via TCP when microphone fails."""
    # This is harder to test because it requires TCP connection
    # For now, we verify the error is logged to stderr

    test_script = """
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Mock sounddevice to always fail
class MockSD:
    class InputStream:
        def __init__(self, *args, **kwargs):
            raise RuntimeError("No default input device found")
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass

sys.modules['sounddevice'] = MockSD()

from whisper_stream import main
sys.argv = [
    'whisper_stream.py',
    '--output-dir', '/tmp/test_mic_fail',
    '--filename-prefix', 'test',
    '--tcp-port', '12399'
]

try:
    main()
except SystemExit:
    pass
"""

    result = subprocess.run(
        ['python3', '-c', test_script],
        capture_output=True,
        cwd=str(Path(__file__).parent.parent.parent),
        timeout=5
    )

    stderr = result.stderr.decode()

    # Should contain error message about microphone
    assert "No default input device" in stderr or "error" in stderr.lower()
