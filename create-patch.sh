#!/usr/bin/env bash

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Only use colors if stdout is a terminal
if [[ ! -t 1 ]]; then
  RED='' GREEN='' YELLOW='' NC=''
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="${SCRIPT_DIR}/patches"

# Usage function
usage() {
  echo "Usage: $(basename "$0") <PR_URL>"
  echo ""
  echo "Fetch a GitHub PR as a patch file for the OpenCode patch repository."
  echo ""
  echo "Example:"
  echo "  $(basename "$0") https://github.com/anomalyco/opencode/pull/16598"
  echo ""
  echo "The patch will be saved to the patches/ directory with auto-numbering."
  exit 0
}

# Parse arguments
if [[ $# -eq 0 ]]; then
  echo -e "${RED}Error: Missing PR URL argument${NC}" >&2
  echo "Usage: $(basename "$0") <PR_URL>" >&2
  echo "Run with --help for more information" >&2
  exit 1
fi

case "$1" in
  --help|-h)
    usage
    ;;
esac

PR_URL="$1"

# Validate PR URL format
# Must match: https://github.com/{org}/{repo}/pull/{number}
if [[ ! "$PR_URL" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)$ ]]; then
  echo -e "${RED}Error: Invalid PR URL format${NC}" >&2
  echo "Expected: https://github.com/{org}/{repo}/pull/{number}" >&2
  exit 1
fi

ORG="${BASH_REMATCH[1]}"
REPO="${BASH_REMATCH[2]}"
PR_NUMBER="${BASH_REMATCH[3]}"

# Create patches directory if it doesn't exist
mkdir -p "$PATCHES_DIR"

# Fetch the patch
TEMP_FILE="/tmp/pr-${PR_NUMBER}.patch"

echo -e "${GREEN}Fetching patch from ${PR_URL}.patch...${NC}"

if ! curl -sSfL "${PR_URL}.patch" -o "$TEMP_FILE"; then
  echo -e "${RED}Error: Failed to fetch patch from ${PR_URL}.patch${NC}" >&2
  exit 1
fi

# Validate downloaded file is non-empty
if [[ ! -s "$TEMP_FILE" ]]; then
  echo -e "${RED}Error: Downloaded patch file is empty${NC}" >&2
  rm -f "$TEMP_FILE"
  exit 1
fi

# Validate it looks like a patch (contains "From " or "Subject:")
if ! grep -q "^From " "$TEMP_FILE" && ! grep -q "^Subject:" "$TEMP_FILE"; then
  echo -e "${RED}Error: Downloaded file does not appear to be a valid patch${NC}" >&2
  rm -f "$TEMP_FILE"
  exit 1
fi

# Extract title from patch
# Look for Subject: line, strip [PATCH N/M] prefixes
SUBJECT_LINE=$(grep "^Subject:" "$TEMP_FILE" | head -1 || true)

if [[ -z "$SUBJECT_LINE" ]]; then
  echo -e "${RED}Error: Could not find Subject line in patch${NC}" >&2
  rm -f "$TEMP_FILE"
  exit 1
fi

# Extract title from Subject: [PATCH N/M] Re: {title} or Subject: {title}
TITLE=$(echo "$SUBJECT_LINE" | sed -E 's/^Subject:(\s*\[PATCH[[:space:]]+[0-9]+/[0-9]+\])?[[:space:]]*(Re:[[:space:]]*)?//I')

# Clean the title: lowercase, replace spaces with hyphens, remove special chars
TITLE=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
TITLE=$(echo "$TITLE" | sed 's/[[:space:]]/-/g')
TITLE=$(echo "$TITLE" | sed 's/[^a-z0-9-]//g')
TITLE=$(echo "$TITLE" | sed 's/-\+/-/g')  # Replace multiple hyphens with single
TITLE=$(echo "$TITLE" | sed 's/^-+//;s/-$//')  # Trim leading/trailing hyphens

# Truncate to ~50 chars for filename sanity
TITLE="${TITLE:0:50}"
TITLE=$(echo "$TITLE" | sed 's/-$//')  # Trim trailing hyphen after truncation

# If title is empty after cleaning, use a default
if [[ -z "$TITLE" ]]; then
  TITLE="untitled"
fi

# Determine sequence number
# Count existing patches in patches/ directory
shopt -s nullglob
PATCH_COUNT=("$PATCHES_DIR"/*.patch)
shopt -u nullglob

NEXT_NUMBER=$((${#PATCH_COUNT[@]} + 1))
SEQ_NUM=$(printf "%04d" "$NEXT_NUMBER")

# Construct filename
FILENAME="${SEQ_NUM}-pr-${PR_NUMBER}-${TITLE}.patch"
DEST_FILE="${PATCHES_DIR}/${FILENAME}"

# Copy from temp to patches directory
cp "$TEMP_FILE" "$DEST_FILE"

# Clean up temp file
rm -f "$TEMP_FILE"

echo -e "${GREEN}Created: ${DEST_FILE}${NC}"
