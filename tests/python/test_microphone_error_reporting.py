"""
Test that microphone errors are properly reported to Lua.
"""
import pytest
import subprocess
import json
import time
import socket
import threading
from pathlib import Path


def test_microphone_error_stays_running():
    """Python server should STAY RUNNING when microphone fails (not crash)."""
    # Create a script that mocks microphone failure
    test_script = '''
import sys

# Mock sounddevice before importing whisper_stream
class MockSD:
    class InputStream:
        def __init__(self, *args, **kwargs):
            raise RuntimeError("No default input device found")
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass

sys.modules['sounddevice'] = MockSD()

# Start TCP client in background to connect
import socket
import threading
import time

def tcp_client():
    time.sleep(0.5)
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect(('127.0.0.1', 12400))
        time.sleep(2)
        sock.close()
    except:
        pass

threading.Thread(target=tcp_client, daemon=True).start()

# Run main
from whisper_stream import main
sys.argv = ['whisper_stream.py', '--output-dir', '/tmp/test', '--filename-prefix', 'test', '--tcp-port', '12400']
main()
'''

    # Server should timeout (stay running), not crash
    try:
        result = subprocess.run(
            ['python3', '-c', test_script],
            capture_output=True,
            timeout=3,
            cwd=str(Path(__file__).parent.parent.parent)
        )
        # If we get here, server exited - that's wrong!
        pytest.fail(f"Server exited with code {result.returncode}, should have stayed running")
    except subprocess.TimeoutExpired:
        # Good! Server stayed running
        pass


def test_microphone_error_sends_tcp_events():
    """Should send error + recording_stopped events via TCP, then stay running."""
    import sys
    from pathlib import Path

    # Add whisper_stream to path
    sys.path.insert(0, str(Path(__file__).parent.parent.parent))

    # Mock sounddevice
    class MockSD:
        class InputStream:
            def __init__(self, *args, **kwargs):
                raise RuntimeError("No default input device found")
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass

    sys.modules['sounddevice'] = MockSD()

    from whisper_stream import ContinuousRecorder

    # Create mock TCP server that captures events
    events = []

    class MockTCPServer:
        def send_event(self, event_type, **kwargs):
            events.append({"type": event_type, **kwargs})
            return True

        def receive_command(self, timeout=0.1):
            return None

    recorder = ContinuousRecorder(
        tcp_server=MockTCPServer(),
        output_dir="/tmp/test",
        filename_prefix="test"
    )

    # Mock VAD to avoid network download
    class MockVAD:
        def eval(self):
            pass

        def __call__(self, audio, sr):
            class Result:
                def item(self):
                    return 0.5

            return Result()

    recorder.vad_model = MockVAD()

    # Start in background - should NOT crash, should send events
    import threading

    def start_recorder():
        try:
            recorder.start()
        except:
            pass  # Might timeout waiting for commands

    thread = threading.Thread(target=start_recorder, daemon=True)
    thread.start()

    # Give it time to process the mic failure
    import time
    time.sleep(0.5)

    # Should have sent error, recording_stopped, and server_ready events
    assert len(events) >= 2
    error_events = [e for e in events if e["type"] == "error"]
    stopped_events = [e for e in events if e["type"] == "recording_stopped"]
    ready_events = [e for e in events if e["type"] == "server_ready"]

    assert len(error_events) == 1, f"Expected 1 error event, got {len(error_events)}"
    assert "device" in error_events[0]["error"].lower()
    assert len(stopped_events) == 1, f"Expected 1 stopped event, got {len(stopped_events)}"
    assert len(ready_events) == 1, f"Expected 1 ready event (after error), got {len(ready_events)}"


def test_error_message_contains_details():
    """Error message should contain helpful details."""
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).parent.parent.parent))

    class MockSD:
        class InputStream:
            def __init__(self, *args, **kwargs):
                raise RuntimeError("No default input device found")

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

    sys.modules['sounddevice'] = MockSD()

    from whisper_stream import ContinuousRecorder

    events = []

    class MockTCPServer:
        def send_event(self, event_type, **kwargs):
            events.append({"type": event_type, **kwargs})
            return True

        def receive_command(self, timeout=0.1):
            return None

    recorder = ContinuousRecorder(
        tcp_server=MockTCPServer(),
        output_dir="/tmp/test",
        filename_prefix="test"
    )

    class MockVAD:
        def eval(self):
            pass

        def __call__(self, audio, sr):
            class Result:
                def item(self):
                    return 0.5

            return Result()

    recorder.vad_model = MockVAD()

    # Start in background
    import threading
    import time

    def start_recorder():
        try:
            recorder.start()
        except:
            pass

    thread = threading.Thread(target=start_recorder, daemon=True)
    thread.start()
    time.sleep(0.5)

    # Check error message
    error_events = [e for e in events if e["type"] == "error"]
    assert len(error_events) == 1

    error_msg = error_events[0]["error"]
    # Should mention it's a microphone error
    assert "Microphone error" in error_msg
    # Should mention the device
    assert "device" in error_msg.lower()
