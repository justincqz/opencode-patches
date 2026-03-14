#!/usr/bin/env bash

set -uo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Only use colors if stdout is a terminal
if [[ ! -t 1 ]]; then
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Configuration
UPSTREAM_URL="https://github.com/anomalyco/opencode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="${SCRIPT_DIR}/patches"
RR_CACHE_DIR="${SCRIPT_DIR}/.rr-cache"
CLONE_DIR="${SCRIPT_DIR}/opencode"

# Usage function
usage() {
  echo "Usage: $(basename "$0") [--help]"
  echo ""
  echo "Apply community patches to OpenCode repository."
  echo ""
  echo "Environment variables:"
  echo "  OPENCODE_TAG    Git tag to clone (e.g., v0.1.0)"
  echo ""
  echo "The tag can also be specified in a .env file in the script directory."
  echo "If neither is provided and stdin is a TTY, you will be prompted."
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
  shift
done

# Resolve tag
resolve_tag() {
  local tag=""

  # Check environment variable
  if [[ -n "${OPENCODE_TAG:-}" ]]; then
    tag="$OPENCODE_TAG"
    echo -e "${BLUE}Using tag from OPENCODE_TAG: ${tag}${NC}"
  # Check .env file
  elif [[ -f "${SCRIPT_DIR}/.env" ]]; then
    # shellcheck disable=SC1090
    source "${SCRIPT_DIR}/.env"
    if [[ -n "${OPENCODE_TAG:-}" ]]; then
      tag="$OPENCODE_TAG"
      echo -e "${BLUE}Using tag from .env file: ${tag}${NC}"
    fi
  fi

  # Interactive prompt if still not set and TTY
  if [[ -z "$tag" && -t 0 ]]; then
    read -r -p "Enter OpenCode tag to clone (e.g., v0.1.0): " tag
  fi

  # Error if still not set
  if [[ -z "$tag" ]]; then
    echo -e "${RED}Error: OPENCODE_TAG not set. Set it in environment or .env file.${NC}" >&2
    exit 1
  fi

  echo "$tag"
}

# Validate tag exists
validate_tag() {
  local tag="$1"
  
  echo -e "${BLUE}Validating tag: ${tag}${NC}"
  
  # Check for the tag (both lightweight and annotated)
  if git ls-remote --tags "$UPSTREAM_URL" | grep -q "refs/tags/${tag}$" || \
     git ls-remote --tags "$UPSTREAM_URL" | grep -q "refs/tags/${tag}^{}$"; then
    return 0
  else
    echo -e "${RED}Error: Tag '${tag}' not found in upstream repository.${NC}" >&2
    exit 1
  fi
}

# Handle existing opencode directory
handle_existing_clone() {
  if [[ -d "$CLONE_DIR" ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Remove existing opencode/ directory? [y/N] " response
      case "$response" in
        [yY][eE][sS]|[yY])
          rm -rf "$CLONE_DIR"
          ;;
        *)
          echo -e "${YELLOW}Aborting.${NC}"
          exit 1
          ;;
      esac
    else
      # CI mode: remove silently
      rm -rf "$CLONE_DIR"
    fi
  fi
}

# Clone repository
clone_repo() {
  local tag="$1"
  
  echo -e "${BLUE}Cloning OpenCode at tag ${tag}...${NC}"
  if ! git clone --branch "$tag" --depth 1 "$UPSTREAM_URL" "$CLONE_DIR"; then
    echo -e "${RED}Error: Failed to clone repository.${NC}" >&2
    exit 1
  fi
}

# Configure rerere
configure_rerere() {
  cd "$CLONE_DIR"
  
  # Enable rerere
  git config rerere.enabled true
  
  # Copy existing rerere cache if present
  if [[ -d "$RR_CACHE_DIR" ]] && [[ "$(ls -A "$RR_CACHE_DIR" 2>/dev/null)" ]]; then
    # Check if there are files other than .gitkeep
    shopt -s nullglob
    local files=("$RR_CACHE_DIR"/*)
    shopt -u nullglob
    
    if [[ ${#files[@]} -gt 0 ]]; then
      # Filter out .gitkeep
      local non_gitkeep=("${files[@]}"/*)
      if [[ ${#non_gitkeep[@]} -gt 0 ]] || [[ -f "$RR_CACHE_DIR"/* && "$(ls -A "$RR_CACHE_DIR" 2>/dev/null | grep -v '^gitkeep$')" ]]; then
        mkdir -p .git/rr-cache
        cp -r "$RR_CACHE_DIR"/* .git/rr-cache/ 2>/dev/null || true
      fi
    fi
  fi
}

# Apply patches
apply_patches() {
  local patch_count=0
  local success_count=0
  
  cd "$CLONE_DIR"
  
  # Find patches sorted alphanumerically
  shopt -s nullglob
  local patches=("$PATCHES_DIR"/*.patch)
  shopt -u nullglob
  
  if [[ ${#patches[@]} -eq 0 ]]; then
    echo -e "${YELLOW}Warning: No patches found in ${PATCHES_DIR}${NC}"
    return 0
  fi
  
  # Sort patches alphanumerically
  IFS=$'\n' patches=($(sort <<<"${patches[*]}"))
  unset IFS
  
  patch_count=${#patches[@]}
  
  for patch in "${patches[@]}"; do
    local patch_name
    patch_name=$(basename "$patch")
    echo -e "${BLUE}Applying: ${patch_name}${NC}"
    
    if git am --3way < "$patch" 2>/dev/null; then
      echo -e "${GREEN}  Applied: ${patch_name}${NC}"
      ((success_count++))
    else
      # Conflict occurred
      echo -e "${YELLOW}  Conflict detected in ${patch_name}${NC}"
      
      # Run rerere to record the conflict
      git rerere || true
      
      # Check for remaining conflicts
      if git diff --name-only --diff-filter=U | grep -q .; then
        local conflicted_files
        conflicted_files=$(git diff --name-only --diff-filter=U)
        
        if [[ -t 0 ]]; then
          # Interactive mode: pause for user to resolve
          echo -e "${YELLOW}Conflicted files:${NC}"
          echo "$conflicted_files"
          echo -e "${YELLOW}Please resolve conflicts in another terminal, then git add the files${NC}"
          read -p "Press Enter when resolved..."
          git add -u
          git am --continue
          ((success_count++))
        else
          # Non-interactive mode: exit with code 2
          echo -e "${RED}Conflicted files:${NC}"
          echo "$conflicted_files"
          echo -e "${RED}Unresolved conflicts in non-interactive mode${NC}" >&2
          cd "$SCRIPT_DIR"
          return 2
        fi
      else
        # No unresolved files, rerere resolved automatically
        git add -u
        git am --continue
        echo -e "${GREEN}  Resolved via rerere: ${patch_name}${NC}"
        ((success_count++))
      fi
    fi
  done
  
  # Return counts via global variables
  PATCH_COUNT="$patch_count"
  SUCCESS_COUNT="$success_count"
}

# Save rerere cache
save_rerere_cache() {
  cd "$CLONE_DIR"
  
  if [[ -d ".git/rr-cache" ]] && [[ "$(ls -A .git/rr-cache 2>/dev/null)" ]]; then
    mkdir -p "$RR_CACHE_DIR"
    cp -r .git/rr-cache/* "$RR_CACHE_DIR/" 2>/dev/null || true
    
    # Remove duplicate .gitkeep if present
    if [[ -f "$RR_CACHE_DIR/.gitkeep" ]]; then
      # Count non-.gitkeep files
      local non_gitkeep
      non_gitkeep=$(find "$RR_CACHE_DIR" -maxdepth 1 -type f ! -name '.gitkeep' | wc -l)
      if [[ "$non_gitkeep" -gt 0 ]]; then
        rm -f "$RR_CACHE_DIR/.gitkeep"
      fi
    fi
  fi
}

# Prepend to README.md
prepend_readme() {
  cd "$CLONE_DIR"
  
  if [[ -f "README.md" ]]; then
    local prepend_line="This build of OpenCode contains fixes and improvements from the community."
    { echo "$prepend_line"; echo ""; cat README.md; } > README.md.tmp && mv README.md.tmp README.md
  fi
}

# Main execution
main() {
  echo -e "${BLUE}OpenCode Patch Application${NC}"
  echo "==========================="
  
  # Resolve and validate tag
  # Using process substitution to capture tag while preserving exit behavior
  TAG=$(resolve_tag) || { local status=$?; echo -e "${RED}Failed to resolve tag${NC}" >&2; exit $status; }
  validate_tag "$TAG"
  
  # Handle existing clone
  handle_existing_clone
  
  # Clone repository
  clone_repo "$TAG"
  
  # Configure rerere
  configure_rerere
  
  # Apply patches
  apply_patches
  local apply_result=$?
  
  # Save rerere cache
  save_rerere_cache
  
  # Prepend to README
  prepend_readme
  
  # Print summary
  echo ""
  echo -e "${BLUE}Summary${NC}"
  echo "--------"
  echo "Tag used: $TAG"
  echo "Patches found: ${PATCH_COUNT:-0}"
  echo "Patches applied: ${SUCCESS_COUNT:-0}"
  
  if [[ $apply_result -eq 0 ]]; then
    echo -e "${GREEN}Success!${NC}"
  elif [[ $apply_result -eq 2 ]]; then
    echo -e "${RED}Failed: Unresolved conflicts in non-interactive mode${NC}"
    exit 2
  else
    echo -e "${YELLOW}Completed with some issues${NC}"
  fi
}

main "$@"
