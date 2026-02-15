"""
Pytest configuration and shared fixtures for whisper_stream tests.
"""
import pytest


@pytest.fixture(autouse=True)
def reset_modules():
    """Reset module state between tests."""
    # Clean up any module-level state if needed
    yield
    # Cleanup after test
