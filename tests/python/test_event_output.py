"""
Unit tests for event output functions in whisper_stream.py
"""
import pytest
import json
import sys
from pathlib import Path
from io import StringIO

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from whisper_stream import output_event, output_error, output_debug


class TestEventOutput:
    """Test event output functions."""

    def test_output_event_basic(self, capsys):
        """Should output JSON event to stdout."""
        output_event("test_event", foo="bar", num=42)

        captured = capsys.readouterr()
        event = json.loads(captured.out.strip())

        assert event["type"] == "test_event"
        assert event["foo"] == "bar"
        assert event["num"] == 42

    def test_output_event_no_kwargs(self, capsys):
        """Should output event with only type."""
        output_event("simple")

        captured = capsys.readouterr()
        event = json.loads(captured.out.strip())

        assert event["type"] == "simple"
        assert len(event) == 1

    def test_output_error(self, capsys):
        """Should output error event."""
        output_error("Something went wrong")

        captured = capsys.readouterr()
        event = json.loads(captured.out.strip())

        assert event["type"] == "error"
        assert event["error"] == "Something went wrong"

    def test_output_debug(self, capsys):
        """Should output debug event."""
        output_debug("Debug message")

        captured = capsys.readouterr()
        event = json.loads(captured.out.strip())

        assert event["type"] == "debug"
        assert event["message"] == "Debug message"

    def test_output_event_complex_data(self, capsys):
        """Should handle complex data structures."""
        output_event("complex",
                    array=[1, 2, 3],
                    nested={"key": "value"},
                    boolean=True,
                    null=None)

        captured = capsys.readouterr()
        event = json.loads(captured.out.strip())

        assert event["array"] == [1, 2, 3]
        assert event["nested"] == {"key": "value"}
        assert event["boolean"] is True
        assert event["null"] is None

    def test_output_error_with_exception(self, capsys):
        """Should convert exceptions to strings."""
        try:
            raise ValueError("Test exception")
        except ValueError as e:
            output_error(e)

        captured = capsys.readouterr()
        event = json.loads(captured.out.strip())

        assert event["type"] == "error"
        assert "Test exception" in event["error"]
