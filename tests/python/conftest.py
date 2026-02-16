"""
Pytest configuration and shared fixtures for whisper_stream tests.
"""
import pytest
import sys
from pathlib import Path

# Add recorders/streaming directory to path so tests can import whisper_stream
spoon_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(spoon_root / "recorders" / "streaming"))


@pytest.fixture(autouse=True)
def reset_modules():
    """Reset module state between tests."""
    # Clean up any module-level state if needed
    yield
    # Cleanup after test
