"""
Unit tests for ContinuousRecorder in whisper_stream.py
"""
import pytest
import numpy as np
import sys
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
import tempfile
import shutil

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from whisper_stream import ContinuousRecorder, normalize_audio


class TestContinuousRecorder:
    """Test ContinuousRecorder class."""

    @pytest.fixture
    def temp_dir(self):
        """Create temporary directory for test outputs."""
        tmpdir = tempfile.mkdtemp()
        yield Path(tmpdir)
        shutil.rmtree(tmpdir)

    @pytest.fixture
    def mock_tcp_server(self):
        """Create mock TCP server."""
        server = Mock()
        server.send_event = Mock(return_value=True)
        return server

    @pytest.fixture
    def mock_vad_model(self):
        """Create mock VAD model."""
        model = Mock()
        # Return high speech probability by default
        model.return_value = Mock(item=Mock(return_value=0.8))
        model.eval = Mock()
        return model

    @pytest.fixture
    def recorder(self, mock_tcp_server, temp_dir, mock_vad_model):
        """Create recorder with mocked dependencies."""
        with patch('whisper_stream.ContinuousRecorder._load_vad_model',
                  return_value=mock_vad_model):
            rec = ContinuousRecorder(
                tcp_server=mock_tcp_server,
                output_dir=str(temp_dir),
                filename_prefix="test",
                silence_threshold=2.0,
                min_chunk_duration=1.0,
                max_chunk_duration=10.0,
                sample_rate=16000,
                perfect_silence_duration=2.0  # Enable for testing
            )
            return rec

    def test_initialization(self, recorder, temp_dir):
        """Should initialize with correct configuration."""
        assert recorder.output_dir == temp_dir
        assert recorder.filename_prefix == "test"
        assert recorder.silence_threshold == 2.0
        assert recorder.min_chunk_duration == 1.0
        assert recorder.max_chunk_duration == 10.0
        assert recorder.sample_rate == 16000
        assert recorder.chunk_num == 0
        assert recorder.running is True
        assert recorder.recording is False

    def test_reset_recording_state(self, recorder):
        """Should reset all recording state."""
        # Set some state
        recorder.chunk_num = 5
        recorder.current_chunk_audio = [np.array([1, 2, 3])]
        recorder.all_audio = [np.array([1, 2, 3])]
        recorder.mic_off = True

        # Reset
        recorder._reset_recording_state()

        assert recorder.chunk_num == 0
        assert recorder.current_chunk_audio == []
        assert recorder.all_audio == []
        assert recorder.mic_off is False
        assert recorder.silence_start_time is None

    def test_check_perfect_silence_all_zeros(self, recorder):
        """Should detect perfect silence."""
        silence_audio = np.zeros(8000, dtype=np.float32)

        # First call - starts timer
        recorder._check_perfect_silence(silence_audio)
        assert recorder.perfect_silence_start_time is not None
        assert not recorder.mic_off

        # Simulate time passing
        with patch('time.time', return_value=recorder.perfect_silence_start_time + 3.0):
            recorder._check_perfect_silence(silence_audio)

        assert recorder.mic_off is True
        assert recorder.running is False

    def test_check_perfect_silence_normal_audio(self, recorder):
        """Should not detect silence for normal audio."""
        normal_audio = np.random.randn(8000).astype(np.float32) * 0.1

        recorder._check_perfect_silence(normal_audio)

        assert recorder.startup_silence_check_done is True
        assert recorder.perfect_silence_start_time is None
        assert not recorder.mic_off

    def test_save_chunk_creates_file(self, recorder, temp_dir):
        """Should save audio chunk to WAV file."""
        # Add audio data
        recorder.current_chunk_audio = [
            np.random.randn(8000).astype(np.float32)
        ]

        with patch('scipy.io.wavfile.write') as mock_write:
            chunk_file = recorder._save_chunk()

        assert chunk_file is not None
        assert "test_chunk_001.wav" in chunk_file
        assert recorder.chunk_num == 1
        assert recorder.current_chunk_audio == []  # Should be reset
        mock_write.assert_called_once()

    def test_save_chunk_empty_audio(self, recorder):
        """Should handle empty audio gracefully."""
        recorder.current_chunk_audio = []

        chunk_file = recorder._save_chunk()

        assert chunk_file is None
        assert recorder.chunk_num == 0  # Should not increment

    def test_save_chunk_increments_counter(self, recorder):
        """Should increment chunk counter on each save."""
        recorder.current_chunk_audio = [np.random.randn(8000).astype(np.float32)]

        with patch('scipy.io.wavfile.write'):
            recorder._save_chunk()
            assert recorder.chunk_num == 1

            recorder.current_chunk_audio = [np.random.randn(8000).astype(np.float32)]
            recorder._save_chunk()
            assert recorder.chunk_num == 2

    def test_detect_voice_activity_speech(self, recorder, mock_vad_model):
        """Should detect speech in audio."""
        audio = np.random.randn(512).astype(np.float32)
        mock_vad_model.return_value.item.return_value = 0.9  # High speech probability

        has_voice = recorder._detect_voice_activity(audio)

        assert has_voice is True

    def test_detect_voice_activity_silence(self, recorder, mock_vad_model):
        """Should detect silence in audio."""
        audio = np.zeros(512, dtype=np.float32)
        mock_vad_model.return_value.item.return_value = 0.1  # Low speech probability

        has_voice = recorder._detect_voice_activity(audio)

        assert has_voice is False

    def test_detect_voice_activity_error_handling(self, recorder, mock_vad_model, mock_tcp_server):
        """Should handle VAD errors gracefully."""
        audio = np.random.randn(512).astype(np.float32)
        mock_vad_model.side_effect = Exception("VAD error")

        has_voice = recorder._detect_voice_activity(audio)

        # Should assume speech on error (safer to keep audio)
        assert has_voice is True
        mock_tcp_server.send_event.assert_called()

    def test_check_max_duration(self, recorder):
        """Should save chunk when max duration exceeded."""
        recorder.current_chunk_audio = [np.random.randn(8000).astype(np.float32)]
        recorder.current_chunk_start_time = 0.0  # Long time ago

        with patch('time.time', return_value=15.0):  # 15 seconds elapsed
            with patch('scipy.io.wavfile.write'):
                result = recorder._check_max_duration()

        assert result is True
        assert recorder.chunk_num == 1

    def test_check_max_duration_not_exceeded(self, recorder):
        """Should not save chunk when under max duration."""
        recorder.current_chunk_audio = [np.random.randn(8000).astype(np.float32)]
        recorder.current_chunk_start_time = 0.0

        with patch('time.time', return_value=5.0):  # 5 seconds (under 10s max)
            result = recorder._check_max_duration()

        assert result is False
        assert recorder.chunk_num == 0  # No save

    def test_emit_chunk_ready(self, recorder, mock_tcp_server):
        """Should emit chunk_ready event."""
        recorder._emit_chunk_ready("/path/to/chunk.wav", is_final=False)

        mock_tcp_server.send_event.assert_called_with(
            "chunk_ready",
            chunk_num=0,
            audio_file="/path/to/chunk.wav",
            is_final=False
        )

    def test_emit_chunk_ready_client_disconnect(self, recorder, mock_tcp_server):
        """Should stop recording when client disconnects."""
        mock_tcp_server.send_event.return_value = False  # Client disconnected

        recorder._emit_chunk_ready("/path/to/chunk.wav")

        assert recorder.running is False

    def test_get_recent_audio_sufficient_samples(self, recorder):
        """Should return recent 512 samples for VAD."""
        # Add enough audio
        for _ in range(5):
            recorder.current_chunk_audio.append(np.random.randn(200).astype(np.float32))

        recent = recorder._get_recent_audio()

        assert recent is not None
        assert len(recent) == 512

    def test_get_recent_audio_insufficient_samples(self, recorder):
        """Should return None when not enough samples."""
        recorder.current_chunk_audio = [np.random.randn(100).astype(np.float32)]

        recent = recorder._get_recent_audio()

        assert recent is None

    def test_process_vad_speech_detected(self, recorder):
        """Should reset silence tracking when speech detected."""
        recorder.silence_start_time = 123.456
        recorder.consecutive_silence_count = 5

        with patch.object(recorder, '_detect_voice_activity', return_value=True):
            recent_audio = np.random.randn(512).astype(np.float32)
            recorder._process_vad(recent_audio)

        assert recorder.silence_start_time is None
        assert recorder.consecutive_silence_count == 0

    def test_process_vad_silence_detected(self, recorder):
        """Should track consecutive silence."""
        recorder.silence_start_time = None
        recorder.consecutive_silence_count = 0

        with patch.object(recorder, '_detect_voice_activity', return_value=False):
            with patch('time.time', return_value=100.0):
                recent_audio = np.zeros(512, dtype=np.float32)

                # First detection
                recorder._process_vad(recent_audio)
                assert recorder.consecutive_silence_count == 1
                assert recorder.silence_start_time is None  # Not enough consecutive

                # Second detection - should start timer
                recorder._process_vad(recent_audio)
                assert recorder.consecutive_silence_count == 2
                assert recorder.silence_start_time == 100.0

    def test_save_complete_recording(self, recorder):
        """Should save complete recording with timestamp."""
        recorder.all_audio = [
            np.random.randn(8000).astype(np.float32),
            np.random.randn(8000).astype(np.float32)
        ]

        with patch('scipy.io.wavfile.write') as mock_write:
            complete_file = recorder._save_complete_recording()

        assert complete_file is not None
        assert "test-" in complete_file
        assert ".wav" in complete_file
        mock_write.assert_called_once()

    def test_save_complete_recording_empty(self, recorder):
        """Should handle empty recording."""
        recorder.all_audio = []

        complete_file = recorder._save_complete_recording()

        assert complete_file is None
