# Test Data Directory

This directory contains permanent test data for WhisperDictation integration tests.

## Structure

```
tests/data/
├── audio/
│   ├── recordings/     # Complete audio recordings from actual usage
│   └── chunks/         # Individual audio chunks
├── transcripts/        # Expected transcription outputs for recordings
└── README.md          # This file
```

## Audio Files

### Recordings
The `audio/recordings/` directory contains real audio files captured from actual usage of the WhisperDictation spoon. These are used for end-to-end integration testing.

- **Format**: WAV files (16kHz, mono, 16-bit)
- **Naming**: `{lang}-{YYYYMMDD}-{HHMMSS}.wav`
  - Example: `en-20260214-183502.wav` (English, Feb 14 2026, 18:35:02)
- **Count**: 45+ recordings

### Chunks
The `audio/chunks/` directory contains individual audio chunks that can be used for testing chunk assembly and transcription.

## Transcripts

The `transcripts/` directory contains expected transcription outputs for each recording. These are automatically generated using the WhisperServer.

- **Format**: Plain text files
- **Naming**: `{basename}.txt` (matches the corresponding audio file)
- **Content**: Expected transcription output from Whisper

## Generating Transcripts

To generate transcripts for new audio files:

```bash
lua tests/helpers/generate_transcripts.lua
```

This script:
1. Checks if WhisperServer is running (starts it if needed)
2. Scans `tests/data/audio/recordings/` for WAV files
3. Transcribes each file using WhisperServer
4. Saves transcripts to `tests/data/transcripts/`
5. Skips files that already have transcripts

## Adding New Test Audio

To add new test audio:

1. Copy WAV files to `tests/data/audio/recordings/`
2. Run the transcript generator:
   ```bash
   lua tests/helpers/generate_transcripts.lua
   ```
3. Verify transcripts in `tests/data/transcripts/`
4. Run tests to confirm:
   ```bash
   busted tests/spec/integration/real_audio_spec.lua
   ```

## Usage in Tests

Tests can access this data using the `Fixtures` helper:

```lua
local Fixtures = require("tests.helpers.fixtures")

-- Get all recordings (includes both fixtures and permanent data)
local recordings = Fixtures.getCompleteRecordings()

for _, recording in ipairs(recordings) do
  print(recording.basename)  -- e.g., "en-20260214-183502"
  print(recording.audio)     -- path to WAV file
  print(recording.transcript) -- path to transcript
  print(recording.lang)      -- e.g., "en"
end
```

## Server Management

Integration tests automatically manage the WhisperServer using `ServerManager`:

```lua
local ServerManager = require("tests.helpers.server_manager")

-- Ensure server is running (start if needed)
local running, msg = ServerManager.ensure({
  host = "127.0.0.1",
  port = 8080,
})

-- Check if server is running
if ServerManager.isRunning() then
  print("Server is ready")
end
```

## Integration with CI/CD

For continuous integration:

1. Ensure whisper-server binary is available
2. Ensure whisper model is downloaded
3. Tests will automatically start the server if needed
4. Or set up server as a service and tests will detect it

## File Sizes

- Total recordings: ~40MB
- Total chunks: ~2MB
- Transcripts: <100KB

## Maintenance

### Cleaning Old Recordings

To remove outdated test recordings:

```bash
# Remove recordings older than 30 days
find tests/data/audio/recordings -name "*.wav" -mtime +30 -delete
find tests/data/transcripts -name "*.txt" -mtime +30 -delete
```

### Regenerating Transcripts

To regenerate all transcripts (e.g., after model update):

```bash
# Remove existing transcripts
rm tests/data/transcripts/*.txt

# Regenerate
lua tests/helpers/generate_transcripts.lua
```

## Version Control

- ✅ Audio files are committed to the repository
- ✅ Transcripts are committed to the repository
- ✅ This ensures consistent test results across environments
- ⚠️ Large binary files increase repository size

If repository size becomes an issue, consider using Git LFS for WAV files.
