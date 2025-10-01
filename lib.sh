#!/usr/bin/env bash

# lib.sh - Reusable workspace setup engine
# Usage: source lib.sh in your project scripts
#
# This library provides functions to automate iTerm window management
# and workspace distribution using AeroSpace window manager.

set -euo pipefail

# =============================================================================
# GLOBAL CONFIGURATION
# =============================================================================

# iTerm bundle identifier for aerospace commands
readonly ITERM_BUNDLE_ID="com.googlecode.iterm2"

# Maximum time to wait for windows to be created
readonly MAX_WAIT_TIME=30

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Standard log message with timestamp
log() {
    echo "[$(date '+%H:%M:%S.%3N')] $*"
}

# Debug level logging
log_debug() {
    echo "[$(date '+%H:%M:%S.%3N')] [DEBUG] $*"
}

# Warning level logging
log_warn() {
    echo "[$(date '+%H:%M:%S.%3N')] [WARN] $*"
}

# Error level logging
log_error() {
    echo "[$(date '+%H:%M:%S.%3N')] [ERROR] $*"
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup existing apps and iTerm windows before starting fresh workspace setup
cleanup() {
    log "=== CLEANUP PHASE START ==="
    log "Starting cleanup process..."

    # Open Leave app to gracefully close other applications
    # Try background first (-gj flags), fallback to foreground
    log_debug "Attempting to open Leave app..."
    if open -gj -a "Leave" 2>/dev/null; then
        log "Successfully opened Leave app (background)"
    elif open -a "Leave" 2>/dev/null; then
        log "Successfully opened Leave app (foreground fallback)"
    else
        log_warn "Failed to open Leave app"
    fi

    # Monitor common development apps and wait for them to close
    local apps=("Code" "Ghostty" "iTerm2" "Terminal" "Google Chrome" "Arc" "Safari")
    local deadline=$((SECONDS + 15)) # 15 second timeout
    log "Waiting for apps to close (timeout: 15s)..."

    local check_count=0
    while [[ $SECONDS -lt $deadline ]]; do
        check_count=$((check_count + 1))
        local still_running=false
        local running_apps=()

        # Check if any monitored apps are still running
        for app in "${apps[@]}"; do
            if pgrep -x "$app" >/dev/null 2>&1; then
                still_running=true
                running_apps+=("$app")
            fi
        done

        # Exit loop if all apps have closed
        if [[ $still_running == false ]]; then
            log "All monitored apps have closed (check #$check_count)"
            break
        else
            log_debug "Check #$check_count: Still running: ${running_apps[*]}"
        fi

        sleep 0.5
    done

    # Force close all existing iTerm windows using AppleScript
    log "Closing existing iTerm windows via AppleScript..."
    if osascript 2>/dev/null <<'EOF'; then
tell application "iTerm"
    if it is running then
        set windowCount to count of windows
        repeat with i from windowCount to 1 by -1
            try
                close window i
            end try
        end repeat
    end if
end tell
EOF
        log "AppleScript window closure completed successfully"
    else
        log_warn "AppleScript window closure failed or iTerm not running"
    fi

    sleep 2

    # Force close any remaining iTerm windows via AeroSpace
    local remaining_windows
    remaining_windows=$(aerospace list-windows --monitor all --app-bundle-id "$ITERM_BUNDLE_ID" --format '%{window-id}' 2>/dev/null | wc -l | tr -d ' ')

    if [[ $remaining_windows -gt 0 ]]; then
        log "Force closing $remaining_windows remaining iTerm windows via AeroSpace..."
        local closed_count=0

        # Close each remaining window individually
        while IFS= read -r wid; do
            if [[ -n $wid ]]; then
                if aerospace close --window-id "$wid" 2>/dev/null; then
                    closed_count=$((closed_count + 1))
                fi
            fi
        done < <(aerospace list-windows --monitor all --app-bundle-id "$ITERM_BUNDLE_ID" --format '%{window-id}' 2>/dev/null)

        log "Closed $closed_count windows via AeroSpace"
        sleep 2
    fi

    log "=== CLEANUP PHASE COMPLETE ==="
    echo
}

# =============================================================================
# WINDOW CREATION FUNCTIONS
# =============================================================================

# Create specified number of iTerm windows in the current directory
create_iterm_windows() {
    local count="$1" # Number of windows to create
    local dir="$PWD" # Current working directory

    log "=== WINDOW CREATION PHASE START ==="
    log "Creating $count iTerm windows in directory: $dir"

    # Create windows one by one using AppleScript
    for ((i = 1; i <= count; i++)); do
        # AppleScript to create new iTerm window and change to current directory
        if osascript 2>/dev/null <<'EOF'; then
tell application "iTerm"
    activate
    set newWindow to (create window with default profile)
    tell current session of newWindow
        write text "cd \"$dir\" && clear"
    end tell
end tell
EOF
            log_debug "Successfully created window $i"
        else
            log_error "Failed to create window $i"
            return 1
        fi

        # Small delay to prevent overwhelming the system
        sleep 0.15

        # Progress update every 3 windows
        if ((i % 3 == 0)); then
            log "Created $i/$count windows..."
        fi
    done

    log "=== WINDOW CREATION PHASE COMPLETE ==="
    echo
}

# Wait for all expected iTerm windows to be created and visible to AeroSpace
wait_for_windows() {
    local expected_count="$1"                   # Expected number of windows
    local deadline=$((SECONDS + MAX_WAIT_TIME)) # Timeout deadline

    log "=== WINDOW WAITING PHASE START ==="
    log "Waiting for $expected_count iTerm windows (timeout: ${MAX_WAIT_TIME}s)..."

    local check_count=0
    while [[ $SECONDS -lt $deadline ]]; do
        check_count=$((check_count + 1))

        # Count current iTerm windows visible to AeroSpace
        local current_count
        current_count=$(aerospace list-windows --monitor all --app-bundle-id "$ITERM_BUNDLE_ID" --format '%{window-id}' 2>/dev/null | wc -l | tr -d ' ')

        # Success condition: found expected number of windows
        if [[ $current_count -eq $expected_count ]]; then
            log "All $expected_count iTerm windows are ready"
            log "=== WINDOW WAITING PHASE COMPLETE ==="
            echo
            return 0
        fi

        # Progress update every 10 checks (5 seconds)
        if ((check_count % 10 == 0)); then
            log "Still waiting... Current: $current_count, Expected: $expected_count"
        fi

        sleep 0.5
    done

    # Timeout reached
    log_error "Timeout waiting for iTerm windows"
    return 1
}

# =============================================================================
# WINDOW QUERY FUNCTIONS
# =============================================================================

# Get list of current iTerm windows with their workspace assignments
get_iterm_windows() {
    aerospace list-windows --monitor all --app-bundle-id "$ITERM_BUNDLE_ID" --format '%{window-id} %{workspace}' 2>/dev/null
}

# Display current distribution of iTerm windows across workspaces
show_distribution() {
    log "Current iTerm window distribution:"
    local distribution
    # Count windows per workspace and sort by workspace number
    distribution=$(get_iterm_windows | awk '{print $2}' | sort | uniq -c | sort -k2)
    echo "$distribution" | while read -r count workspace; do
        log "  Workspace $workspace: $count windows"
    done
}

# =============================================================================
# WINDOW MOVEMENT FUNCTIONS
# =============================================================================

# Check if a window is on the specified workspace
_on_ws() {
    local wid="$1" # Window ID
    local ws="$2"  # Workspace number

    # Search for window ID on the specified workspace
    aerospace list-windows --monitor all --format '%{window-id} %{workspace}' |
        awk -v id="$wid" -v want="$ws" '$1==id && $2==want { ok=1 } END { exit ok?0:1 }'
}

# Move window to workspace with verification and retry logic
_move_with_verify() {
    local wid="$1" # Window ID to move
    local ws="$2"  # Target workspace
    local tries=0  # Attempt counter

    # Retry up to 5 times
    while ((tries < 5)); do
        tries=$((tries + 1))

        # Attempt to move window
        aerospace move-node-to-workspace --window-id "$wid" "$ws" >/dev/null 2>&1
        sleep 0.1

        # Verify the move was successful
        if _on_ws "$wid" "$ws"; then
            log_debug "Successfully moved window $wid -> $ws (attempt $tries)"
            return 0
        fi
    done

    log_error "Failed to move window $wid -> $ws after $tries attempts"
    return 1
}

# Distribute iTerm windows across workspaces according to plan arrays
distribute_windows() {
    local -n plan_ws=$1  # Array of target workspaces (nameref)
    local -n plan_ct=$2  # Array of window counts per workspace (nameref)
    local total_terms=$3 # Expected total number of windows

    log "=== WINDOW DISTRIBUTION PHASE START ==="
    log "Distributing iTerm windows using pool strategy..."

    # Create pool of all available iTerm windows
    mapfile -t POOL < <(aerospace list-windows --monitor all \
        --app-bundle-id "$ITERM_BUNDLE_ID" \
        --format '%{window-id}')

    log "Window pool created with ${#POOL[@]} windows (expected: $total_terms)"

    # Validate we have windows to work with
    if [[ ${#POOL[@]} -eq 0 ]]; then
        log_error "No windows in pool!"
        return 1
    fi

    local idx=0         # Current index in window pool
    local total_moved=0 # Count of successfully moved windows

    # Process each workspace in the distribution plan
    for i in "${!plan_ws[@]}"; do
        local ws="${plan_ws[$i]}"   # Target workspace
        local need="${plan_ct[$i]}" # Number of windows needed

        log "Processing workspace $ws (needs $need windows)..."

        # Move required number of windows to this workspace
        for ((k = 0; k < need; k++)); do
            # Check if we've exhausted the window pool
            if [[ $idx -ge ${#POOL[@]} ]]; then
                log_error "Pool exhausted!"
                return 1
            fi

            local wid="${POOL[$idx]}"
            idx=$((idx + 1))

            # Move window with verification
            if _move_with_verify "$wid" "$ws"; then
                total_moved=$((total_moved + 1))
            fi
        done
    done

    log "Distribution complete! Moved $total_moved/$total_terms windows"
    log "=== WINDOW DISTRIBUTION PHASE COMPLETE ==="
    echo
}

# =============================================================================
# APPLICATION MANAGEMENT FUNCTIONS
# =============================================================================

# Open application and position it on specified workspace
open_and_position_app() {
    local app_name="$1"  # Application name
    local workspace="$2" # Target workspace
    local bundle_id="$3" # App bundle identifier
    local url="${4:-}"   # Optional URL to open

    log_debug "Opening $app_name..." >&2

    # Build open command, optionally with URL
    local open_cmd="open -a \"$app_name\""
    if [[ -n $url ]]; then
        open_cmd="$open_cmd \"$url\""
    fi

    # Attempt to open the application
    if eval "$open_cmd" 2>/dev/null; then
        log "$app_name opened successfully" >&2
        sleep 2

        # Find the application window (retry up to 10 times)
        local app_wid
        local attempts=0
        while [[ $attempts -lt 10 ]]; do
            app_wid=$(aerospace list-windows --monitor all --app-bundle-id "$bundle_id" --format '%{window-id}' 2>/dev/null | head -n1)
            if [[ -n $app_wid ]]; then
                break
            fi
            sleep 0.5
            attempts=$((attempts + 1))
        done

        # Move window to target workspace if found
        if [[ -n $app_wid ]]; then
            if aerospace move-node-to-workspace --window-id "$app_wid" "$workspace" 2>/dev/null; then
                log "Moved $app_name to workspace $workspace (window ID: $app_wid)" >&2
                echo "$app_wid" # Return window ID to stdout
                return 0
            else
                log_warn "Failed to move $app_name to workspace $workspace" >&2
            fi
        else
            log_warn "Could not find $app_name window ID after $attempts attempts" >&2
        fi
    else
        log_warn "Failed to open $app_name" >&2
    fi

    return 1
}

# =============================================================================
# WINDOW INTERACTION FUNCTIONS
# =============================================================================

# Focus on an iTerm window in the specified workspace
focus_iterm_ws() {
    local ws="$1" # Target workspace

    # Find first iTerm window on the workspace
    local wid
    wid=$(aerospace list-windows --workspace "$ws" \
        --app-bundle-id com.googlecode.iterm2 \
        --format '%{window-id}' | head -n1)

    # Focus the window if found
    [[ -n $wid ]] && aerospace focus --window-id "$wid"
}

# Write command to current iTerm window using AppleScript
iterm_write() {
    local cmd="$*" # Command to write

    # Escape special characters for AppleScript
    local esc
    esc=$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')

    # Send command to current iTerm session
    osascript <<OSA
tell application "iTerm"
    if (count of windows) = 0 then return
    tell current session of current window to write text "$esc"
end tell
OSA
}

# Populate workspace iTerm windows with commands
populate_ws() {
    local ws="$1" # Target workspace
    shift
    local -a cmds=("$@") # Array of commands to distribute

    # Get all iTerm windows on the workspace
    mapfile -t ids < <(aerospace list-windows --workspace "$ws" \
        --app-bundle-id com.googlecode.iterm2 \
        --format '%{window-id}')

    # Determine how many commands we can actually run
    local n_min=${#cmds[@]}
    ((${#ids[@]} < n_min)) && n_min=${#ids[@]}

    # Focus each window and send corresponding command
    for ((i = 0; i < n_min; i++)); do
        aerospace focus --window-id "${ids[$i]}"
        sleep 0.1
        iterm_write "${cmds[$i]}"
        sleep 0.05
    done
}

# =============================================================================
# WINDOW SEARCH AND MANIPULATION FUNCTIONS
# =============================================================================

# Find iTerm window ID by title pattern (case-insensitive)
_find_iterm_wid_by_title() {
    local pat="$1" # Search pattern

    aerospace list-windows --monitor all \
        --app-bundle-id com.googlecode.iterm2 \
        --format '%{window-id} %{window-title}' |
        awk -v p="$pat" 'BEGIN{IGNORECASE=1} $0 ~ p {print $1; exit}'
}

# Move/nudge window by title pattern in specified direction
nudge_by_title() {
    local pat="$1"        # Title pattern to match
    local dir="$2"        # Direction to move (left/right/up/down)
    local times="${3:-1}" # Number of times to nudge (default: 1)

    # Find window matching the pattern
    local wid
    wid=$(_find_iterm_wid_by_title "$pat") || true

    if [[ -z $wid ]]; then
        echo "nudge_by_title: no match for /$pat/"
        return 1
    fi

    # Focus window and perform nudge operations
    aerospace focus --window-id "$wid"
    sleep 0.15

    for ((i = 0; i < times; i++)); do
        aerospace move "$dir" || true
        sleep 0.12
    done
}

# Resize window by title pattern
resize_by_title() {
    local pat="$1"   # Title pattern to match
    local dim="$2"   # Dimension to resize (width/height)
    local delta="$3" # Amount to resize (+/-)

    # Find window matching the pattern
    local wid
    wid=$(_find_iterm_wid_by_title "$pat") || true

    if [[ -z $wid ]]; then
        echo "resize_by_title: no match for: $pat"
        return 1
    fi

    # Resize the window
    aerospace resize "$dim" "$delta" --window-id "$wid"
}

# =============================================================================
# SUMMARY AND REPORTING FUNCTIONS
# =============================================================================

# Show final summary comparing target vs actual window distribution
show_final_summary() {
    local -n target_ws=$1 # Target workspace array (nameref)
    local -n target_ct=$2 # Target count array (nameref)
    local total_terms=$3  # Expected total windows

    log "=== FINAL SUMMARY ==="
    echo

    # Display current distribution
    log "Final iTerm window distribution:"
    show_distribution

    echo
    log "Target vs Actual comparison:"

    # Get actual distribution data
    local actual_dist
    actual_dist=$(get_iterm_windows | awk '{print $2}' | sort | uniq -c | sort -k2)

    # Compare each workspace target vs actual
    for i in "${!target_ws[@]}"; do
        local ws="${target_ws[$i]}"
        local target="${target_ct[$i]}"

        # Extract actual count for this workspace
        local actual
        actual=$(echo "$actual_dist" | awk -v ws="$ws" '$2==ws {print $1}' || echo "0")

        # Report match or mismatch
        if [[ $actual -eq $target ]]; then
            log "  ✓ Workspace $ws: $actual/$target terminals (MATCH)"
        else
            log_warn "  ✗ Workspace $ws: $actual/$target terminals (MISMATCH)"
        fi
    done

    # Calculate and report total
    local total_actual
    total_actual=$(echo "$actual_dist" | awk '{sum+=$1} END {print sum+0}')
    log "Total windows: $total_actual/$total_terms"

    log "=== FINAL SUMMARY COMPLETE ==="
}
