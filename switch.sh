#!/bin/bash

# Detect if 4K monitor is connected
DISPLAY_INFO=$(system_profiler SPDisplaysDataType 2>/dev/null)

if echo "$DISPLAY_INFO" | grep -q "3840 x 2160"; then
    CONFIG="$HOME/.config/aerospace/aerospace-4k.toml"
else
    CONFIG="$HOME/.config/aerospace/aerospace-laptop.toml"
fi

# Symlink to the active config
ln -sf "$CONFIG" "$HOME/.config/aerospace/aerospace.toml"

# Reload AeroSpace
aerospace reload-config

if echo "$DISPLAY_INFO" | grep -q "3840 x 2160"; then
    export SKETCHYBAR_MINIMAL=0
else
    export SKETCHYBAR_MINIMAL=1
fi

sketchybar --reload
