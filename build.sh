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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLONE_DIR="${SCRIPT_DIR}/opencode"
DIST_DIR="${SCRIPT_DIR}/dist"
BUILD_SCRIPT="./packages/opencode/script/build.ts"

# Usage function
usage() {
  echo "Usage: $(basename "$0") [--help]"
  echo ""
  echo "Build OpenCode from the cloned and patched repository."
  echo ""
  echo "This script:"
  echo "  1. Checks that opencode/ directory exists"
  echo "  2. Verifies bun is available and version >= 1.3"
  echo "  3. Resolves version from OPENCODE_TAG or package.json"
  echo "  4. Installs dependencies and runs the build"
  echo "  5. Copies build output to dist/"
  echo ""
  echo "Environment variables:"
  echo "  OPENCODE_TAG    Git tag to use for version (e.g., v1.2.26)"
  echo ""
  echo "The tag can also be specified in a .env file in the script directory."
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

# Check that opencode directory exists
check_clone_dir() {
  if [[ ! -d "$CLONE_DIR" ]]; then
    echo -e "${RED}Error: opencode/ directory not found. Run ./apply.sh first to clone and patch OpenCode.${NC}" >&2
    exit 1
  fi
}

# Check that bun is available, upgrading PATH to a newer mise-installed bun if needed
check_bun() {
  # Helper: test if a bun binary meets the version requirement
  _bun_version_ok() {
    local b="$1"
    local ver major minor
    ver=$("$b" --version 2>/dev/null | sed 's/^bun v//')
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    [[ -n "$major" && -n "$minor" ]] && \
      { [[ "$major" -gt 1 ]] || [[ "$major" -eq 1 && "$minor" -ge 3 ]]; }
  }

  # Check the bun currently on PATH
  if command -v bun &> /dev/null && _bun_version_ok "$(command -v bun)"; then
    return 0
  fi

  # Search mise installs for a suitable bun
  local mise_bun_base="${HOME}/.local/share/mise/installs/bun"
  if [[ -d "$mise_bun_base" ]]; then
    local candidate
    # Iterate versions numerically descending (latest first)
    while IFS= read -r candidate; do
      local bun_bin="${mise_bun_base}/${candidate}/bin/bun"
      if [[ -x "$bun_bin" ]] && _bun_version_ok "$bun_bin"; then
        export PATH="${mise_bun_base}/${candidate}/bin:${PATH}"
        echo -e "${YELLOW}Using mise-installed bun ${candidate} from ${mise_bun_base}/${candidate}/bin${NC}"
        return 0
      fi
    done < <(ls -1 "$mise_bun_base" | sort -V -r)
  fi

  if ! command -v bun &> /dev/null; then
    echo -e "${RED}Error: bun is not installed. Please install bun >= 1.3 from https://bun.sh${NC}" >&2
  else
    local ver
    ver=$(bun --version | sed 's/^bun v//')
    echo -e "${RED}Error: bun version $ver is too old. Please upgrade to bun >= 1.3${NC}" >&2
  fi
  exit 1
}

# Check bun version >= 1.3 (informational — check_bun already enforces this)
check_bun_version() {
  local bun_version
  bun_version=$(bun --version | sed 's/^bun v//')
  echo -e "${GREEN}Using bun version: ${bun_version}${NC}"
}

# Resolve version from OPENCODE_TAG or .env file
resolve_version() {
  local version=""
  
  # Check environment variable
  if [[ -n "${OPENCODE_TAG:-}" ]]; then
    version="${OPENCODE_TAG#v}"
  # Check .env file
  elif [[ -f "${SCRIPT_DIR}/.env" ]]; then
    # shellcheck disable=SC1090
    source "${SCRIPT_DIR}/.env"
    if [[ -n "${OPENCODE_TAG:-}" ]]; then
      version="${OPENCODE_TAG#v}"
    fi
  fi
  
  # Fallback: read from package.json
  if [[ -z "$version" ]] && [[ -f "${CLONE_DIR}/packages/opencode/package.json" ]]; then
    version=$(grep '"version"' "${CLONE_DIR}/packages/opencode/package.json" | sed 's/.*"version": *"\([^"]*\)".*/\1/')
  fi
  
  if [[ -z "$version" ]]; then
    echo -e "${RED}Error: Could not resolve version. Set OPENCODE_TAG in environment or .env file.${NC}" >&2
    exit 1
  fi
  
  echo "$version"
}

# Install dependencies
install_deps() {
  cd "$CLONE_DIR"
  echo -e "${BLUE}Installing dependencies...${NC}"
  bun install
}

# Run the build
run_build() {
  cd "$CLONE_DIR"
  echo -e "${BLUE}Running build...${NC}"
  # --skip-install avoids cross-platform `bun install --os="*" --cpu="*"` which
  # causes integrity errors for optional packages targeting other platforms.
  bun run "${BUILD_SCRIPT}" --single --skip-install
}

# Copy build output to dist/
copy_output() {
  mkdir -p "$DIST_DIR"
  local src_dir="${CLONE_DIR}/packages/opencode/dist"
  
  if [[ ! -d "$src_dir" ]]; then
    echo -e "${RED}Error: Build output not found at ${src_dir}${NC}" >&2
    exit 1
  fi
  
  echo -e "${BLUE}Copying build output to dist/...${NC}"
  cp -r "${src_dir}"/* "${DIST_DIR}/"
}

# Show success message
show_success() {
  local version="$1"
  
  # Find the platform directory
  local platform_dir
  platform_dir=$(ls -d "${DIST_DIR}"/opencode-linux-* 2>/dev/null | head -1)
  
  if [[ -z "$platform_dir" ]]; then
    platform_dir="${DIST_DIR}"
  fi
  
  local binary="${platform_dir}/bin/opencode"
  local size
  size=$(du -sh "${DIST_DIR}" 2>/dev/null | cut -f1)
  
  echo ""
  echo -e "${GREEN}Build complete!${NC}"
  echo "---------------"
  echo "Version: $version"
  echo "Output:  dist/"
  echo "Size:    $size"
  if [[ -f "$binary" ]]; then
    echo "Binary:  ${binary}"
    echo ""
    echo "Run the binary:"
    echo "  ${binary} --version"
  fi
}

# Main execution
main() {
  echo -e "${BLUE}OpenCode Build${NC}"
  echo "=============="
  
  # Run checks
  check_clone_dir
  check_bun
  check_bun_version
  
  # Resolve version
  VERSION=$(resolve_version)
  echo -e "${GREEN}Building version: ${VERSION}${NC}"
  
  # Set environment variables for build
  export OPENCODE_VERSION="$VERSION"
  export OPENCODE_CHANNEL=latest
  
  # Build steps
  install_deps
  run_build
  copy_output
  
  # Show success
  show_success "$VERSION"
}

main "$@"
