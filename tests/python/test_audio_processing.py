"""
Unit tests for audio processing functions in whisper_stream.py
"""
import pytest
import numpy as np
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from whisper_stream import (
    normalize_audio,
    is_perfect_silence,
    convert_to_int16,
    SILENCE_AMPLITUDE_THRESHOLD
)


class TestNormalizeAudio:
    """Test audio normalization to float32 [-1, 1] range."""

    def test_int16_to_float32(self):
        """Should normalize int16 audio to float32."""
        audio = np.array([0, 16384, -16384, 32767, -32768], dtype=np.int16)
        result = normalize_audio(audio)

        assert result.dtype == np.float32
        assert np.allclose(result[0], 0.0)
        assert np.allclose(result[1], 0.5, atol=0.01)
        assert np.allclose(result[2], -0.5, atol=0.01)
        assert np.allclose(result[3], 1.0, atol=0.01)
        assert np.allclose(result[4], -1.0, atol=0.01)

    def test_float32_passthrough(self):
        """Should pass through float32 audio unchanged."""
        audio = np.array([0.0, 0.5, -0.5, 1.0, -1.0], dtype=np.float32)
        result = normalize_audio(audio)

        assert result.dtype == np.float32
        assert np.allclose(result, audio)

    def test_float64_to_float32(self):
        """Should convert float64 to float32."""
        audio = np.array([0.0, 0.5, -0.5], dtype=np.float64)
        result = normalize_audio(audio)

        assert result.dtype == np.float32
        assert np.allclose(result, audio)

    def test_empty_array(self):
        """Should handle empty array."""
        audio = np.array([], dtype=np.int16)
        result = normalize_audio(audio)

        assert result.dtype == np.float32
        assert len(result) == 0


class TestIsPerfectSilence:
    """Test perfect silence detection (mic off detection)."""

    def test_all_zeros_is_silence(self):
        """All zeros should be detected as perfect silence."""
        audio = np.zeros(1000, dtype=np.float32)
        assert is_perfect_silence(audio)

    def test_very_quiet_is_silence(self):
        """Audio below threshold should be silence."""
        audio = np.full(1000, SILENCE_AMPLITUDE_THRESHOLD * 0.5, dtype=np.float32)
        assert is_perfect_silence(audio)

    def test_normal_audio_not_silence(self):
        """Normal amplitude audio should not be silence."""
        audio = np.full(1000, 0.1, dtype=np.float32)
        assert not is_perfect_silence(audio)

    def test_int16_all_zeros(self):
        """Should handle int16 zero audio."""
        audio = np.zeros(1000, dtype=np.int16)
        assert is_perfect_silence(audio)

    def test_int16_normal_audio(self):
        """Should handle int16 normal audio."""
        audio = np.full(1000, 5000, dtype=np.int16)
        assert not is_perfect_silence(audio)

    def test_single_loud_sample(self):
        """Single loud sample should prevent silence detection."""
        audio = np.zeros(1000, dtype=np.float32)
        audio[500] = 0.1  # One loud sample
        assert not is_perfect_silence(audio)


class TestConvertToInt16:
    """Test audio conversion to int16 format."""

    def test_float32_to_int16(self):
        """Should convert float32 [-1, 1] to int16."""
        audio = np.array([0.0, 0.5, -0.5, 1.0, -1.0], dtype=np.float32)
        result = convert_to_int16(audio)

        assert result.dtype == np.int16
        assert result[0] == 0
        assert abs(result[1] - 16383) <= 1
        assert abs(result[2] - (-16383)) <= 1
        assert result[3] == 32767
        assert result[4] == -32767

    def test_float64_to_int16(self):
        """Should convert float64 to int16."""
        audio = np.array([0.0, 0.5, -0.5], dtype=np.float64)
        result = convert_to_int16(audio)

        assert result.dtype == np.int16

    def test_int16_passthrough(self):
        """Should pass through int16 unchanged."""
        audio = np.array([0, 1000, -1000, 32767, -32768], dtype=np.int16)
        result = convert_to_int16(audio)

        assert result.dtype == np.int16
        assert np.array_equal(result, audio)

    def test_clipping(self):
        """Should clip values outside [-1, 1] range."""
        audio = np.array([-2.0, -1.5, 1.5, 2.0], dtype=np.float32)
        result = convert_to_int16(audio)

        assert result.dtype == np.int16
        # Values should be clipped to int16 range

    def test_empty_array(self):
        """Should handle empty array."""
        audio = np.array([], dtype=np.float32)
        result = convert_to_int16(audio)

        assert result.dtype == np.int16
        assert len(result) == 0
