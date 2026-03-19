#!/bin/bash

DISPLAY_INFO=$(system_profiler SPDisplaysDataType 2>/dev/null)

if echo "$DISPLAY_INFO" | grep -q "3840 x 2160"; then
    cp ~/.config/aerospace/aerospace-monitor.toml ~/.config/aerospace/aerospace.toml
    launchctl setenv SKETCHYBAR_MINIMAL 0
else
    cp ~/.config/aerospace/aerospace-laptop.toml ~/.config/aerospace/aerospace.toml
    launchctl setenv SKETCHYBAR_MINIMAL 1
fi

aerospace reload-config
~/.config/sketchybar/sb.sh restart
