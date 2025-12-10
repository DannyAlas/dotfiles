#!/bin/bash
set -e

# Configuration
PUBLIC_REMOTE="public"
INTERNAL_REMOTE="internal"
BRANCH="main"

# Bridge PC author info
BRIDGE_NAME="${BRIDGE_AUTHOR_NAME:-Bridge PC}"
BRIDGE_EMAIL="${BRIDGE_AUTHOR_EMAIL:-bridge@internal.local}"

usage() {
    echo "Usage: $0 <direction>"
    echo "  public-to-internal  - Relay commits from public to internal"
    echo "  internal-to-public  - Relay commits from internal to public"
    exit 1
}

relay_commits() {
    local SOURCE_REMOTE="$1"
    local TARGET_REMOTE="$2"
    local DIRECTION="$3"
    local TRACKING_REF="refs/bridge/last-synced-${DIRECTION}"
    local WORK_BRANCH="bridge-work-${DIRECTION}"
    
    echo "=== Bridge Relay: $DIRECTION ==="
    echo "Bridge Author: $BRIDGE_NAME <$BRIDGE_EMAIL>"
    
    # Fetch source and store ref
    git fetch "$SOURCE_REMOTE" "$BRANCH"
    SOURCE_HEAD=$(git rev-parse FETCH_HEAD)
    
    # Check if target has the branch and fetch if so
    if git ls-remote --exit-code "$TARGET_REMOTE" "$BRANCH" >/dev/null 2>&1; then
        git fetch "$TARGET_REMOTE" "$BRANCH"
        git checkout -B "$WORK_BRANCH" FETCH_HEAD
    else
        echo "Target branch doesn't exist yet - creating fresh"
        git checkout --orphan "$WORK_BRANCH"
        git rm -rf . 2>/dev/null || true
    fi
    
    # Get last synced position
    if git show-ref --verify --quiet "$TRACKING_REF"; then
        LAST_SYNCED=$(git rev-parse "$TRACKING_REF")
    else
        echo "First run - processing all commits"
        LAST_SYNCED=$(git rev-list --max-parents=0 "$SOURCE_HEAD" | tail -1)
    fi
    
    # New commits to relay (oldest first)
    COMMITS=$(git rev-list --reverse "$LAST_SYNCED".."$SOURCE_HEAD")
    
    if [ -z "$COMMITS" ]; then
        echo "No new commits to process."
        return 0
    fi
    
    echo "Processing $(echo "$COMMITS" | wc -l) commit(s)..."
    
    for COMMIT in $COMMITS; do
        ORIGINAL_MSG=$(git log -1 --format="%B" "$COMMIT")
        SHORT_HASH=$(git rev-parse --short "$COMMIT")
        
        echo "--- Replaying $SHORT_HASH ---"
        
        # Cherry-pick (may result in no changes if already applied)
        if ! git cherry-pick --no-commit "$COMMIT" 2>/dev/null; then
            echo "Cherry-pick failed or empty - resetting"
            git reset --hard
            git update-ref "$TRACKING_REF" "$COMMIT"
            continue
        fi
        
        # Check if there are any changes to commit
        if git diff --cached --quiet; then
            echo "No changes - skipping"
            git update-ref "$TRACKING_REF" "$COMMIT"
            continue
        fi
        
        GIT_AUTHOR_NAME="$BRIDGE_NAME" \
        GIT_AUTHOR_EMAIL="$BRIDGE_EMAIL" \
        GIT_COMMITTER_NAME="$BRIDGE_NAME" \
        GIT_COMMITTER_EMAIL="$BRIDGE_EMAIL" \
        git commit -m "$ORIGINAL_MSG"
        
        git update-ref "$TRACKING_REF" "$COMMIT"
        echo "✓ Replayed"
    done
    
    echo "Pushing to target..."
    git push "$TARGET_REMOTE" "$WORK_BRANCH:$BRANCH"
    
    echo "=== Complete ==="
}

case "${1:-}" in
    public-to-internal)
        relay_commits "$PUBLIC_REMOTE" "$INTERNAL_REMOTE" "public-to-internal"
        ;;
    internal-to-public)
        relay_commits "$INTERNAL_REMOTE" "$PUBLIC_REMOTE" "internal-to-public"
        ;;
    *)
        usage
        ;;
esac
