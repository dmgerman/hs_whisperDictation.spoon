#!/bin/bash
# Audio Routing Test Infrastructure
# Provides functions for virtual audio device management with BlackHole

# ==============================================================================
# Audio Device Management
# ==============================================================================

# Check if BlackHole is installed
# Returns: 0 if installed, 1 if not
function is_blackhole_installed() {
  # Check if BlackHole 2ch device exists
  system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole 2ch"
  return $?
}

# Assert that BlackHole is installed, fail with instructions if not
function assert_blackhole_installed() {
  if ! is_blackhole_installed; then
    echo ""
    echo "ERROR: BlackHole virtual audio device not found"
    echo ""
    echo "To install:"
    echo "  brew install blackhole-2ch"
    echo ""
    echo "Then restart Hammerspoon and re-run tests."
    echo ""
    echo "See: https://github.com/ExistentialAudio/BlackHole"
    echo ""
    return 1
  fi
  return 0
}

# Get current audio input device
function get_current_input_device() {
  # Prefer SwitchAudioSource if available (faster and more reliable)
  if command -v SwitchAudioSource &>/dev/null; then
    SwitchAudioSource -t input -c
    return $?
  fi

  # Fallback to osascript
  local device=$(osascript -e 'tell application "System Events" to get name of (get first item of (get audio devices whose input volume is not missing value))' 2>/dev/null)
  echo "$device"
}

# Set audio input device by name
# Args: device_name
function set_input_device() {
  local device_name="$1"

  # Use SwitchAudioSource if available (faster and more reliable)
  if command -v SwitchAudioSource &>/dev/null; then
    SwitchAudioSource -s "$device_name" -t input >/dev/null 2>&1
    return $?
  fi

  # Fallback to osascript (slower but built-in)
  # Note: This method is less reliable than SwitchAudioSource
  osascript <<EOF 2>/dev/null
    tell application "System Events"
      tell application "System Preferences"
        reveal pane id "com.apple.preference.sound"
      end tell
      delay 0.5
      tell process "System Preferences"
        click radio button "Input" of tab group 1 of window "Sound"
        delay 0.2
        select (row 1 of table 1 of scroll area 1 of tab group 1 of window "Sound" whose value of text field 1 is "$device_name")
      end tell
      quit application "System Preferences"
    end tell
EOF
  return $?
}

# Store current input device for later restoration
_ORIGINAL_INPUT_DEVICE=""

# Setup virtual audio routing - switches to BlackHole input
# Returns: 0 on success, 1 on failure
function setup_virtual_audio() {
  # Check BlackHole is installed
  if ! assert_blackhole_installed; then
    return 1
  fi

  # Store current input device
  _ORIGINAL_INPUT_DEVICE=$(get_current_input_device)
  echo "  # Stored original input device: $_ORIGINAL_INPUT_DEVICE"

  # Switch to BlackHole 2ch
  if ! set_input_device "BlackHole 2ch"; then
    echo "ERROR: Failed to switch to BlackHole 2ch"
    return 1
  fi

  # Wait for device switch to take effect
  sleep 0.5

  return 0
}

# Restore original audio input device
function teardown_virtual_audio() {
  if [ -n "$_ORIGINAL_INPUT_DEVICE" ]; then
    echo "  # Restoring audio input to: $_ORIGINAL_INPUT_DEVICE"
    set_input_device "$_ORIGINAL_INPUT_DEVICE" || echo "  # Warning: Failed to restore audio device"
    sleep 0.5
  else
    echo "  # Warning: No original audio device stored, cannot restore"
  fi
}

# ==============================================================================
# Audio Playback
# ==============================================================================

# Play an audio file to BlackHole output (virtual mic input)
# Args: audio_file
# Returns: 0 on success, 1 on failure
function play_fixture_to_virtual() {
  local audio_file="$1"

  if [ ! -f "$audio_file" ]; then
    echo "ERROR: Audio file not found: $audio_file"
    return 1
  fi

  # Use afplay to play audio to default output
  # Since we've set BlackHole as input, we need to play to BlackHole output
  # which then becomes available as input to recording software

  # Check if SwitchAudioSource is available for output switching
  if command -v SwitchAudioSource &>/dev/null; then
    # Store current output device
    local original_output=$(SwitchAudioSource -c -t output)

    # Switch output to BlackHole 2ch
    SwitchAudioSource -s "BlackHole 2ch" -t output

    # Play audio file (blocks until complete)
    afplay "$audio_file"

    # Restore original output
    SwitchAudioSource -s "$original_output" -t output
  else
    # Fallback: use sox to play directly to BlackHole
    # This requires sox to be installed
    if command -v sox &>/dev/null; then
      sox "$audio_file" -t coreaudio "BlackHole 2ch"
    else
      echo "ERROR: Neither SwitchAudioSource nor sox available for audio playback"
      echo "Install one of:"
      echo "  brew install switchaudio-osx"
      echo "  brew install sox"
      return 1
    fi
  fi

  return 0
}

# Play audio fixture asynchronously (in background)
# Args: audio_file
# Returns: PID of background process
function play_fixture_to_virtual_async() {
  local audio_file="$1"
  play_fixture_to_virtual "$audio_file" &
  echo $!
}

# ==============================================================================
# Helper Functions
# ==============================================================================

# Check if required tools are installed
function check_audio_tools() {
  local missing=()

  if ! command -v SwitchAudioSource &>/dev/null && ! command -v sox &>/dev/null; then
    missing+=("SwitchAudioSource or sox")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: Missing required tools:"
    for tool in "${missing[@]}"; do
      echo "  - $tool"
    done
    echo ""
    echo "Install with:"
    echo "  brew install switchaudio-osx  # for SwitchAudioSource"
    echo "  brew install sox              # alternative audio tool"
    return 1
  fi

  return 0
}

# List available audio input devices
function list_input_devices() {
  system_profiler SPAudioDataType 2>/dev/null | grep -A 5 "Audio Devices:" | grep -v "Audio Devices:" || echo "No devices found"
}

# ==============================================================================
# Cleanup on Exit
# ==============================================================================

# Automatically restore audio device on script exit
trap teardown_virtual_audio EXIT

# ==============================================================================
# Usage Examples
# ==============================================================================

# Example usage:
#
#   # Setup BlackHole routing
#   setup_virtual_audio || exit 1
#
#   # Play fixture audio (blocks until complete)
#   play_fixture_to_virtual "tests/fixtures/test_audio.wav"
#
#   # Start recording with BlackHole as input
#   # (your recorder will capture the played audio)
#
#   # Cleanup (automatic via trap, or manual)
#   teardown_virtual_audio
