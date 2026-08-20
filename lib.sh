#!/usr/bin/env bash

# lib.sh - Reusable workspace setup engine. Source this from project scripts;
# it provides the iTerm window management + AeroSpace distribution helpers
# run.sh and projects/*.sh build on.

set -euo pipefail

readonly ITERM_BUNDLE_ID="com.googlecode.iterm2"
readonly MAX_WAIT_TIME=30

log() {
    echo "[$(date '+%H:%M:%S.%3N')] $*"
}

log_debug() {
    echo "[$(date '+%H:%M:%S.%3N')] [DEBUG] $*"
}

log_warn() {
    echo "[$(date '+%H:%M:%S.%3N')] [WARN] $*"
}

log_error() {
    echo "[$(date '+%H:%M:%S.%3N')] [ERROR] $*"
}

# ── Cleanup ──────────────────────────────────────────────────────────────────

cleanup() {
    log "=== CLEANUP PHASE START ==="
    log "Starting cleanup process..."

    # "Leave" quits other running apps for us; try background first, fall
    # back to foreground if that fails
    log_debug "Attempting to open Leave app..."
    if open -gj -a "Leave" 2>/dev/null; then
        log "Successfully opened Leave app (background)"
    elif open -a "Leave" 2>/dev/null; then
        log "Successfully opened Leave app (foreground fallback)"
    else
        log_warn "Failed to open Leave app"
    fi

    # give common dev apps up to 15s to actually close before moving on
    local apps=("Code" "Ghostty" "iTerm2" "Terminal" "Google Chrome" "Arc" "Safari")
    local deadline=$((SECONDS + 15))
    log "Waiting for apps to close (timeout: 15s)..."

    local check_count=0
    while [[ $SECONDS -lt $deadline ]]; do
        check_count=$((check_count + 1))
        local still_running=false
        local running_apps=()

        for app in "${apps[@]}"; do
            if pgrep -x "$app" >/dev/null 2>&1; then
                still_running=true
                running_apps+=("$app")
            fi
        done

        if [[ $still_running == false ]]; then
            log "All monitored apps have closed (check #$check_count)"
            break
        else
            log_debug "Check #$check_count: Still running: ${running_apps[*]}"
        fi

        sleep 0.5
    done

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

    # AppleScript won't catch everything — mop up any stragglers via AeroSpace
    local remaining_windows
    remaining_windows=$(aerospace list-windows --monitor all --app-bundle-id "$ITERM_BUNDLE_ID" --format '%{window-id}' 2>/dev/null | wc -l | tr -d ' ')

    if [[ $remaining_windows -gt 0 ]]; then
        log "Force closing $remaining_windows remaining iTerm windows via AeroSpace..."
        local closed_count=0

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

# ── Window creation ──────────────────────────────────────────────────────────

create_iterm_windows() {
    local count="$1"
    local dir="$PWD"

    log "=== WINDOW CREATION PHASE START ==="
    log "Creating $count iTerm windows in directory: $dir"

    for ((i = 1; i <= count; i++)); do
        if osascript 2>/dev/null <<EOF; then
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

        # don't fire AppleScript events at iTerm faster than it can keep up
        sleep 0.15

        if ((i % 3 == 0)); then
            log "Created $i/$count windows..."
        fi
    done

    log "=== WINDOW CREATION PHASE COMPLETE ==="
    echo
}

wait_for_windows() {
    local expected_count="$1"
    local deadline=$((SECONDS + MAX_WAIT_TIME))

    log "=== WINDOW WAITING PHASE START ==="
    log "Waiting for $expected_count iTerm windows (timeout: ${MAX_WAIT_TIME}s)..."

    local check_count=0
    while [[ $SECONDS -lt $deadline ]]; do
        check_count=$((check_count + 1))

        local current_count
        current_count=$(aerospace list-windows --monitor all --app-bundle-id "$ITERM_BUNDLE_ID" --format '%{window-id}' 2>/dev/null | wc -l | tr -d ' ')

        if [[ $current_count -eq $expected_count ]]; then
            log "All $expected_count iTerm windows are ready"
            log "=== WINDOW WAITING PHASE COMPLETE ==="
            echo
            return 0
        fi

        if ((check_count % 10 == 0)); then
            log "Still waiting... Current: $current_count, Expected: $expected_count"
        fi

        sleep 0.5
    done

    log_error "Timeout waiting for iTerm windows"
    return 1
}

# ── Window queries ───────────────────────────────────────────────────────────

get_iterm_windows() {
    aerospace list-windows --monitor all --app-bundle-id "$ITERM_BUNDLE_ID" --format '%{window-id} %{workspace}' 2>/dev/null
}

show_distribution() {
    log "Current iTerm window distribution:"
    local distribution
    distribution=$(get_iterm_windows | awk '{print $2}' | sort | uniq -c | sort -k2)
    echo "$distribution" | while read -r count workspace; do
        log "  Workspace $workspace: $count windows"
    done
}

# ── Window movement ──────────────────────────────────────────────────────────

_on_ws() {
    local wid="$1"
    local ws="$2"

    aerospace list-windows --monitor all --format '%{window-id} %{workspace}' |
        awk -v id="$wid" -v want="$ws" '$1==id && $2==want { ok=1 } END { exit ok?0:1 }'
}

_move_with_verify() {
    local wid="$1"
    local ws="$2"
    local tries=0

    while ((tries < 5)); do
        tries=$((tries + 1))

        aerospace move-node-to-workspace --window-id "$wid" "$ws" >/dev/null 2>&1
        sleep 0.1

        if _on_ws "$wid" "$ws"; then
            log_debug "Successfully moved window $wid -> $ws (attempt $tries)"
            return 0
        fi
    done

    log_error "Failed to move window $wid -> $ws after $tries attempts"
    return 1
}

# takes plan_ws/plan_ct by nameref since bash can't return arrays
distribute_windows() {
    local -n plan_ws=$1
    local -n plan_ct=$2
    local total_terms=$3

    log "=== WINDOW DISTRIBUTION PHASE START ==="
    log "Distributing iTerm windows using pool strategy..."

    mapfile -t POOL < <(aerospace list-windows --monitor all \
        --app-bundle-id "$ITERM_BUNDLE_ID" \
        --format '%{window-id}')

    log "Window pool created with ${#POOL[@]} windows (expected: $total_terms)"

    if [[ ${#POOL[@]} -eq 0 ]]; then
        log_error "No windows in pool!"
        return 1
    fi

    local idx=0
    local total_moved=0

    for i in "${!plan_ws[@]}"; do
        local ws="${plan_ws[$i]}"
        local need="${plan_ct[$i]}"

        log "Processing workspace $ws (needs $need windows)..."

        for ((k = 0; k < need; k++)); do
            if [[ $idx -ge ${#POOL[@]} ]]; then
                log_error "Pool exhausted!"
                return 1
            fi

            local wid="${POOL[$idx]}"
            idx=$((idx + 1))

            if _move_with_verify "$wid" "$ws"; then
                total_moved=$((total_moved + 1))
            fi
        done
    done

    log "Distribution complete! Moved $total_moved/$total_terms windows"
    log "=== WINDOW DISTRIBUTION PHASE COMPLETE ==="
    echo
}

# ── Application management ───────────────────────────────────────────────────

open_and_position_app() {
    local app_name="$1"
    local workspace="$2"
    local bundle_id="$3"
    local url="${4:-}"

    log_debug "Opening $app_name..." >&2

    local open_cmd="open -a \"$app_name\""
    if [[ -n $url ]]; then
        open_cmd="$open_cmd \"$url\""
    fi

    if eval "$open_cmd" 2>/dev/null; then
        log "$app_name opened successfully" >&2
        sleep 2

        # AeroSpace can take a moment to see a freshly-opened window, retry for it
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

        if [[ -n $app_wid ]]; then
            if aerospace move-node-to-workspace --window-id "$app_wid" "$workspace" 2>/dev/null; then
                log "Moved $app_name to workspace $workspace (window ID: $app_wid)" >&2
                echo "$app_wid"
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

# ── Window interaction ───────────────────────────────────────────────────────

focus_iterm_ws() {
    local ws="$1"

    local wid
    wid=$(aerospace list-windows --workspace "$ws" \
        --app-bundle-id com.googlecode.iterm2 \
        --format '%{window-id}' | head -n1)

    [[ -n $wid ]] && aerospace focus --window-id "$wid"
}

iterm_write() {
    local cmd="$*"

    local esc
    esc=$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')

    osascript <<OSA
tell application "iTerm"
    if (count of windows) = 0 then return
    tell current session of current window to write text "$esc"
end tell
OSA
}

populate_ws() {
    local ws="$1"
    shift
    local -a cmds=("$@")

    mapfile -t ids < <(aerospace list-windows --workspace "$ws" \
        --app-bundle-id com.googlecode.iterm2 \
        --format '%{window-id}')

    # only run as many commands as we have windows to receive them
    local n_min=${#cmds[@]}
    ((${#ids[@]} < n_min)) && n_min=${#ids[@]}

    for ((i = 0; i < n_min; i++)); do
        aerospace focus --window-id "${ids[$i]}"
        sleep 0.1
        iterm_write "${cmds[$i]}"
        sleep 0.05
    done
}

# ── Window search ────────────────────────────────────────────────────────────

_find_iterm_wid_by_title() {
    local pat="$1"

    aerospace list-windows --monitor all \
        --app-bundle-id com.googlecode.iterm2 \
        --format '%{window-id} %{window-title}' |
        awk -v p="$pat" 'BEGIN{IGNORECASE=1} $0 ~ p {print $1; exit}'
}

nudge_by_title() {
    local pat="$1"
    local dir="$2"
    local times="${3:-1}"

    local wid
    wid=$(_find_iterm_wid_by_title "$pat") || true

    if [[ -z $wid ]]; then
        echo "nudge_by_title: no match for /$pat/"
        return 1
    fi

    aerospace focus --window-id "$wid"
    sleep 0.15

    for ((i = 0; i < times; i++)); do
        aerospace move "$dir" || true
        sleep 0.12
    done
}

resize_by_title() {
    local pat="$1"
    local dim="$2"
    local delta="$3"

    local wid
    wid=$(_find_iterm_wid_by_title "$pat") || true

    if [[ -z $wid ]]; then
        echo "resize_by_title: no match for: $pat"
        return 1
    fi

    aerospace resize "$dim" "$delta" --window-id "$wid"
}

# ── Summary ──────────────────────────────────────────────────────────────────

show_final_summary() {
    local -n target_ws=$1
    local -n target_ct=$2
    local total_terms=$3

    log "=== FINAL SUMMARY ==="
    echo

    log "Final iTerm window distribution:"
    show_distribution

    echo
    log "Target vs Actual comparison:"

    local actual_dist
    actual_dist=$(get_iterm_windows | awk '{print $2}' | sort | uniq -c | sort -k2)

    for i in "${!target_ws[@]}"; do
        local ws="${target_ws[$i]}"
        local target="${target_ct[$i]}"

        local actual
        actual=$(echo "$actual_dist" | awk -v ws="$ws" '$2==ws {print $1}' || echo "0")

        if [[ $actual -eq $target ]]; then
            log "  ✓ Workspace $ws: $actual/$target terminals (MATCH)"
        else
            log_warn "  ✗ Workspace $ws: $actual/$target terminals (MISMATCH)"
        fi
    done

    local total_actual
    total_actual=$(echo "$actual_dist" | awk '{sum+=$1} END {print sum+0}')
    log "Total windows: $total_actual/$total_terms"

    log "=== FINAL SUMMARY COMPLETE ==="
}
