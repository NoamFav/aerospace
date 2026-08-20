#!/usr/bin/env bash

# Usage: ./run.sh <project> — sources lib.sh + projects/<project>.sh, then
# builds that project's iTerm window layout via AeroSpace.

set -euo pipefail

# start every project from the same workspace
aerospace workspace Q

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <project>"
    echo "Available projects:"
    ls -1 "$SCRIPT_DIR/projects/"*.sh 2>/dev/null | xargs -I {} basename {} .sh | sed 's/^/  /'
    exit 1
fi

PROJECT="$1"
PROJECT_SCRIPT="$SCRIPT_DIR/projects/${PROJECT}.sh"

if [[ ! -f "$PROJECT_SCRIPT" ]]; then
    echo "Error: Project '$PROJECT' not found at $PROJECT_SCRIPT"
    echo "Available projects:"
    ls -1 "$SCRIPT_DIR/projects/"*.sh 2>/dev/null | xargs -I {} basename {} .sh | sed 's/^/  /'
    exit 1
fi

log "========================================"
log "WORKSPACE SETUP FOR PROJECT: $PROJECT"
log "========================================"
log "Loading project configuration from: $PROJECT_SCRIPT"
echo

source "$PROJECT_SCRIPT"

if [[ -z "${PLAN_WS:-}" ]] || [[ -z "${PLAN_CT:-}" ]] || [[ -z "${TOTAL_TERMS:-}" ]]; then
    log_error "Project $PROJECT missing required configuration (PLAN_WS, PLAN_CT, TOTAL_TERMS)"
    log_error "Required variables:"
    log_error "  PLAN_WS: Array of target workspaces"
    log_error "  PLAN_CT: Array of window counts per workspace"
    log_error "  TOTAL_TERMS: Total number of terminal windows"
    exit 1
fi

if [[ ${#PLAN_WS[@]} -ne ${#PLAN_CT[@]} ]]; then
    log_error "Project $PROJECT has mismatched PLAN_WS and PLAN_CT arrays"
    log_error "PLAN_WS has ${#PLAN_WS[@]} elements, PLAN_CT has ${#PLAN_CT[@]} elements"
    exit 1
fi

expected_total=0
for count in "${PLAN_CT[@]}"; do
    expected_total=$((expected_total + count))
done

if [[ $expected_total -ne $TOTAL_TERMS ]]; then
    log_error "Project $PROJECT: PLAN_CT sum ($expected_total) doesn't match TOTAL_TERMS ($TOTAL_TERMS)"
    log_error "Plan breakdown:"
    for i in "${!PLAN_WS[@]}"; do
        log_error "  Workspace ${PLAN_WS[$i]}: ${PLAN_CT[$i]} windows"
    done
    exit 1
fi

log "Project validation passed"
log "Current directory: $PWD"
echo

main() {
    cleanup
    sleep 2

    create_iterm_windows "$TOTAL_TERMS"

    if ! wait_for_windows "$TOTAL_TERMS"; then
        local current_count
        current_count=$(aerospace list-windows --monitor all \
            --app-bundle-id "$ITERM_BUNDLE_ID" \
            --format '%{window-id}' 2>/dev/null | wc -l | tr -d ' ')

        log_warn "Expected $TOTAL_TERMS terminals but found $current_count"

        # bail if there's not enough to work with
        if [[ $current_count -lt 8 ]]; then
            log_error "Too few terminals created ($current_count < 8). Aborting."
            log_error "Minimum viable workspace requires at least 8 terminals"
            exit 1
        else
            # missing a few is fine, keep going instead of failing outright
            log_warn "Continuing with $current_count terminals..."
        fi
    fi

    log "=== INITIAL DISTRIBUTION CHECK ==="
    show_distribution
    echo

    # optional project hooks below — only run if the project script defines them
    if declare -f setup_other_apps >/dev/null; then
        log "=== OTHER APPLICATIONS PHASE START ==="
        setup_other_apps
        log "=== OTHER APPLICATIONS PHASE COMPLETE ==="
        echo
    fi

    distribute_windows PLAN_WS PLAN_CT "$TOTAL_TERMS"

    # let AeroSpace settle after all the window moves
    log "Allowing AeroSpace to settle..."
    sleep 1

    show_final_summary PLAN_WS PLAN_CT "$TOTAL_TERMS"

    echo
    log "========================================"
    log "WORKSPACE SETUP COMPLETE!"
    log "========================================"

    sleep 2

    if declare -f populate_all >/dev/null; then
        log "=== POPULATION PHASE START ==="
        populate_all
        log "=== POPULATION PHASE COMPLETE ==="
        echo
    fi

    if declare -f final_layout >/dev/null; then
        log "=== FINAL LAYOUT ADJUSTMENTS ==="
        final_layout
        log "=== LAYOUT ADJUSTMENTS COMPLETE ==="
        echo
    fi

    if declare -f final_focus >/dev/null; then
        final_focus
    fi

    log "========================================"
    log "ALL PHASES COMPLETE!"
    log "========================================"
}

main
