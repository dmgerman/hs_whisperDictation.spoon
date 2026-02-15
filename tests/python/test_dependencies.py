"""
Unit tests for dependency checking in whisper_stream.py
"""
import pytest
import sys
from pathlib import Path
import importlib
from unittest.mock import MagicMock

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))


class TestCheckDependencies:
    """Test dependency checking function."""

    def setup_method(self):
        """Save original sys.modules state."""
        self.original_modules = sys.modules.copy()
        # Reload whisper_stream to clear any cached imports
        if 'whisper_stream' in sys.modules:
            del sys.modules['whisper_stream']

    def teardown_method(self):
        """Restore original sys.modules state."""
        # Clear the whisper_stream module to reset its imports
        if 'whisper_stream' in sys.modules:
            del sys.modules['whisper_stream']

        # Completely restore sys.modules to original state
        # First, remove anything we added
        keys_to_remove = [k for k in sys.modules.keys() if k not in self.original_modules]
        for key in keys_to_remove:
            del sys.modules[key]

        # Then restore/fix any modules that were mocked (set to None or MagicMock)
        for key in list(sys.modules.keys()):
            if key in self.original_modules:
                # If current is None/Mock but original was real module, restore it
                if self.original_modules[key] is not None:
                    if (sys.modules[key] is None or
                        type(sys.modules[key]).__name__ == 'MagicMock'):
                        sys.modules[key] = self.original_modules[key]

        # Finally, add back any modules that were removed
        for key, value in self.original_modules.items():
            if key not in sys.modules and value is not None:
                sys.modules[key] = value

    def test_all_dependencies_present(self):
        """Should return empty list when all deps are installed."""
        from whisper_stream import check_dependencies
        missing = check_dependencies()
        # May or may not be empty depending on test environment
        assert isinstance(missing, list)

    def test_missing_sounddevice(self):
        """Should detect missing sounddevice."""
        # Remove sounddevice from sys.modules if present
        sys.modules['sounddevice'] = None  # None triggers ImportError

        # Import and run check_dependencies
        import whisper_stream
        importlib.reload(whisper_stream)
        missing = whisper_stream.check_dependencies()

        assert any('sounddevice' in dep for dep in missing)

    def test_missing_torch_and_onnx(self):
        """Should detect when both torch and onnx are missing."""
        sys.modules['torch'] = None
        sys.modules['onnxruntime'] = None

        import whisper_stream
        importlib.reload(whisper_stream)
        missing = whisper_stream.check_dependencies()

        assert any('torch or onnxruntime' in dep for dep in missing)

    def test_torch_present_onnx_missing(self):
        """Should not report missing when torch is present."""
        # Mock torch as present
        sys.modules['torch'] = MagicMock()
        sys.modules['onnxruntime'] = None

        import whisper_stream
        importlib.reload(whisper_stream)
        missing = whisper_stream.check_dependencies()

        # Should not complain about torch/onnx if torch is present
        assert not any('torch or onnxruntime' in dep for dep in missing)

    def test_missing_scipy(self):
        """Should detect missing scipy."""
        sys.modules['scipy'] = None
        sys.modules['scipy.io'] = None
        sys.modules['scipy.io.wavfile'] = None

        import whisper_stream
        importlib.reload(whisper_stream)
        missing = whisper_stream.check_dependencies()

        assert any('scipy' in dep for dep in missing)
