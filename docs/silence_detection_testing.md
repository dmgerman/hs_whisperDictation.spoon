# Silence Detection Testing

## Overview

Comprehensive test suite for silence detection functionality using recorded silent audio files.

## Test File

**Location**: `tests/python/test_silence_detection.py`

## Test Coverage (8 tests)

### 1. Basic File Validation
- ✅ `test_silent_file_has_zero_amplitude` - Verifies /tmp/empty.wav is actually silent
- ✅ `test_silent_file_loading` - Tests loading silent WAV file with FileAudioSource
- ✅ `test_silent_file_chunking` - Tests reading chunks from silent file

### 2. Silence Detection Logic
- ✅ `test_silence_warning_on_perfect_silence` - Verifies silence warning after 2+ seconds
- ✅ `test_silence_detection_with_mock_tcp` - Tests basic event emission

### 3. File Management
- ✅ `test_output_directory_creation` - Ensures nested directories are created
- ✅ `test_chunk_files_created_in_output_dir` - Verifies WAV files written to correct location
- ✅ `test_is_perfect_silence_function` - Tests silence detection utility

## Bugs Fixed

### 1. Directory Creation Bug
**Problem**: `FileNotFoundError` when output directory doesn't exist

**Fix**: Added `self.output_dir.mkdir(parents=True, exist_ok=True)` in:
- `_save_chunk()` (line 389)
- `_save_complete_recording()` (line 670)

### 2. Real-time Simulation Missing
**Problem**: File streaming processed all audio instantly, preventing time-based silence detection

**Fix**: Added `time.sleep(self.audio_source.chunk_duration)` in file streaming loop
- File now streams in real-time (5 seconds of audio takes ~5 seconds)
- Silence detection timing works correctly

## Test Audio File

**File**: `/tmp/empty.wav`
- Duration: 5 seconds
- Sample rate: 16000 Hz
- Max amplitude: 0.0 (perfect silence)

Created with: `sox -n -r 16000 -c 1 -b 16 /tmp/empty.wav trim 0 5`

## Silence Detection Behavior

**Threshold**: `PERFECT_SILENCE_DURATION_AT_START = 2.0` seconds

When perfect silence is detected for 2+ seconds at recording start:
1. `silence_warning` event is emitted
2. `self.mic_off = True` flag is set
3. `self.running = False` stops recording
4. Prevents recording when microphone is off/muted

## Test Results

**Total**: 451 tests (374 Lua + 77 Python)
- Previous: 443 tests (374 Lua + 69 Python)
- Added: 8 new silence detection tests

All tests passing ✅

## Usage

```bash
# Run all silence detection tests
python3 -m pytest tests/python/test_silence_detection.py -v

# Run specific test
python3 -m pytest tests/python/test_silence_detection.py::TestSilenceDetection::test_silence_warning_on_perfect_silence -v
```

## Related Files

- `whisper_stream.py` - Core silence detection logic
- `tests/python/test_file_integration.py` - File input integration tests
- `tests/python/test_microphone_error_reporting.py` - Microphone failure tests
