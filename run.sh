#!/usr/bin/env bash

# run.sh - Workspace setup runner
# Usage: ./run.sh <project>
#
# This script orchestrates the complete workspace setup process by:
# 1. Loading project-specific configurations from projects/ directory
# 2. Validating configuration parameters
# 3. Executing the multi-phase setup workflow
# 4. Providing comprehensive logging and error handling

set -euo pipefail

# =============================================================================
# INITIAL SETUP
# =============================================================================

# Switch to workspace Q (presumed starting workspace)
aerospace workspace Q

# Get absolute path to script directory for reliable file resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the workspace management library
source "$SCRIPT_DIR/lib.sh"

# =============================================================================
# ARGUMENT VALIDATION AND PROJECT LOADING
# =============================================================================

# Validate command line arguments
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <project>"
    echo "Available projects:"
    # List all available project files without .sh extension
    ls -1 "$SCRIPT_DIR/projects/"*.sh 2>/dev/null | xargs -I {} basename {} .sh | sed 's/^/  /'
    exit 1
fi

PROJECT="$1"
PROJECT_SCRIPT="$SCRIPT_DIR/projects/${PROJECT}.sh"

# Verify project configuration file exists
if [[ ! -f "$PROJECT_SCRIPT" ]]; then
    echo "Error: Project '$PROJECT' not found at $PROJECT_SCRIPT"
    echo "Available projects:"
    ls -1 "$SCRIPT_DIR/projects/"*.sh 2>/dev/null | xargs -I {} basename {} .sh | sed 's/^/  /'
    exit 1
fi

# =============================================================================
# PROJECT CONFIGURATION LOADING AND VALIDATION
# =============================================================================

# Load project configuration
log "========================================"
log "WORKSPACE SETUP FOR PROJECT: $PROJECT"
log "========================================"
log "Loading project configuration from: $PROJECT_SCRIPT"
echo

# Source the project-specific configuration
source "$PROJECT_SCRIPT"

# Validate required project configuration variables
if [[ -z "${PLAN_WS:-}" ]] || [[ -z "${PLAN_CT:-}" ]] || [[ -z "${TOTAL_TERMS:-}" ]]; then
    log_error "Project $PROJECT missing required configuration (PLAN_WS, PLAN_CT, TOTAL_TERMS)"
    log_error "Required variables:"
    log_error "  PLAN_WS: Array of target workspaces"
    log_error "  PLAN_CT: Array of window counts per workspace"
    log_error "  TOTAL_TERMS: Total number of terminal windows"
    exit 1
fi

# Validate array consistency - workspace and count arrays must have same length
if [[ ${#PLAN_WS[@]} -ne ${#PLAN_CT[@]} ]]; then
    log_error "Project $PROJECT has mismatched PLAN_WS and PLAN_CT arrays"
    log_error "PLAN_WS has ${#PLAN_WS[@]} elements, PLAN_CT has ${#PLAN_CT[@]} elements"
    exit 1
fi

# Calculate expected total from plan and validate against TOTAL_TERMS
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

# =============================================================================
# MAIN WORKFLOW ORCHESTRATION
# =============================================================================

# Main function that orchestrates the entire workspace setup process
main() {
    # =========================================================================
    # PHASE 1: CLEANUP
    # =========================================================================
    # Clean up existing applications and iTerm windows
    cleanup
    sleep 2

    # =========================================================================
    # PHASE 2: WINDOW CREATION
    # =========================================================================
    # Create the required number of iTerm terminal windows
    create_iterm_windows "$TOTAL_TERMS"

    # =========================================================================
    # PHASE 3: WINDOW AVAILABILITY VERIFICATION
    # =========================================================================
    # Wait for all windows to be created and visible to AeroSpace
    if ! wait_for_windows "$TOTAL_TERMS"; then
        # Fallback handling if we don't get exactly the expected number
        local current_count
        current_count=$(aerospace list-windows --monitor all \
            --app-bundle-id "$ITERM_BUNDLE_ID" \
            --format '%{window-id}' 2>/dev/null | wc -l | tr -d ' ')

        log_warn "Expected $TOTAL_TERMS terminals but found $current_count"

        # Abort if we have too few windows to work with
        if [[ $current_count -lt 8 ]]; then
            log_error "Too few terminals created ($current_count < 8). Aborting."
            log_error "Minimum viable workspace requires at least 8 terminals"
            exit 1
        else
            log_warn "Continuing with $current_count terminals..."
            # Note: This allows for graceful degradation if slightly fewer windows are created
        fi
    fi

    # =========================================================================
    # PHASE 4: INITIAL STATE VERIFICATION
    # =========================================================================
    # Show where windows are currently distributed before organization
    log "=== INITIAL DISTRIBUTION CHECK ==="
    show_distribution
    echo

    # =========================================================================
    # PHASE 5: ADDITIONAL APPLICATION SETUP (OPTIONAL)
    # =========================================================================
    # Open other applications if project defines setup_other_apps function
    if declare -f setup_other_apps >/dev/null; then
        log "=== OTHER APPLICATIONS PHASE START ==="
        setup_other_apps
        log "=== OTHER APPLICATIONS PHASE COMPLETE ==="
        echo
    fi

    # =========================================================================
    # PHASE 6: WINDOW DISTRIBUTION
    # =========================================================================
    # Distribute iTerm windows across workspaces according to project plan
    distribute_windows PLAN_WS PLAN_CT "$TOTAL_TERMS"

    # =========================================================================
    # PHASE 7: SYSTEM STABILIZATION
    # =========================================================================
    # Allow AeroSpace window manager to settle after window movements
    log "Allowing AeroSpace to settle..."
    sleep 1

    # =========================================================================
    # PHASE 8: FINAL DISTRIBUTION VERIFICATION
    # =========================================================================
    # Show final summary comparing target vs actual distribution
    show_final_summary PLAN_WS PLAN_CT "$TOTAL_TERMS"

    echo
    log "========================================"
    log "WORKSPACE SETUP COMPLETE!"
    log "========================================"

    sleep 2

    # =========================================================================
    # PHASE 9: COMMAND POPULATION (OPTIONAL)
    # =========================================================================
    # Populate terminal windows with project-specific commands
    if declare -f populate_all >/dev/null; then
        log "=== POPULATION PHASE START ==="
        populate_all
        log "=== POPULATION PHASE COMPLETE ==="
        echo
    fi

    # =========================================================================
    # PHASE 10: FINAL LAYOUT ADJUSTMENTS (OPTIONAL)
    # =========================================================================
    # Apply final window positioning, resizing, or other layout tweaks
    if declare -f final_layout >/dev/null; then
        log "=== FINAL LAYOUT ADJUSTMENTS ==="
        final_layout
        log "=== LAYOUT ADJUSTMENTS COMPLETE ==="
        echo
    fi

    # =========================================================================
    # PHASE 11: FINAL FOCUS POSITIONING (OPTIONAL)
    # =========================================================================
    # Set final focus to preferred window/workspace
    if declare -f final_focus >/dev/null; then
        final_focus
    fi

    # =========================================================================
    # COMPLETION
    # =========================================================================
    log "========================================"
    log "ALL PHASES COMPLETE!"
    log "========================================"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Execute the main workflow with all command line arguments
main
