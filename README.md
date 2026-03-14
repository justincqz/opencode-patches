# OpenCode Patches

This repository contains community patches for [OpenCode](https://github.com/anomalyco/opencode) that can be applied to any tagged version of the upstream repository. It provides automation for fetching GitHub PRs as patches and applying them to create a customized OpenCode build with community fixes and improvements.

## Repository Structure

```
opencode-patches/
├── .env.example          # Example environment configuration
├── .gitignore            # Git ignore rules
├── .rr-cache/            # rerere conflict resolution cache
├── patches/              # Directory containing patch files
├── apply.sh              # Main script to apply patches to OpenCode
├── create-patch.sh      # Helper script to fetch GitHub PRs as patches
└── README.md             # This file
```

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/your-org/opencode-patches.git
   cd opencode-patches
   ```

2. Copy the example environment file and set your desired OpenCode version:
   ```bash
   cp .env.example .env
   # Edit .env and set OPENCODE_TAG (e.g., OPENCODE_TAG=v0.1.0)
   ```

3. Run the patch application:
   ```bash
   ./apply.sh
   ```

4. Find your patched OpenCode in the `opencode/` directory.

## Configuration

### OPENCODE_TAG Environment Variable

The `OPENCODE_TAG` variable specifies which version of OpenCode to clone and patch. It can be set in three ways (in order of precedence):

1. **Environment variable**: `OPENCODE_TAG=v0.1.0 ./apply.sh`
2. **.env file**: Create a `.env` file in the repository root:
   ```bash
   OPENCODE_TAG=v0.1.0
   ```
3. **Interactive prompt**: If neither of the above is set and stdin is a TTY, you will be prompted to enter a tag.

### Tag Validation

Before cloning, the script validates that the tag exists in the upstream repository using `git ls-remote --tags`. If the tag is not found, the script exits with an error.

## Usage: apply.sh

The main script that clones OpenCode at a specified tag and applies all patches.

### Synopsis

```bash
./apply.sh [--help]
```

### Options

- `--help` - Display usage information

### Environment Variables

- `OPENCODE_TAG` - Git tag to clone (e.g., v0.1.0)

### Exit Codes

- `0` - Success, all patches applied
- `1` - Error (invalid tag, failed clone, missing patches directory)
- `2` - Conflicts detected in non-interactive mode (CI)

### Examples

**With environment variable:**
```bash
OPENCODE_TAG=v0.1.0 ./apply.sh
```

**With .env file:**
```bash
./apply.sh
# (ensure OPENCODE_TAG is set in .env)
```

**In CI/non-interactive mode:**
```bash
export OPENCODE_TAG=v0.1.0
./apply.sh
```

## Usage: create-patch.sh

A helper script to fetch GitHub PRs and save them as patch files in the `patches/` directory.

### Synopsis

```bash
./create-patch.sh <PR_URL>
./create-patch.sh --help
```

### Arguments

- `PR_URL` - Full URL to a GitHub pull request (e.g., https://github.com/anomalyco/opencode/pull/16598)

### Examples

```bash
# Fetch a single PR
./create-patch.sh https://github.com/anomalyco/opencode/pull/16598

# The patch will be saved to patches/ with auto-numbering
# e.g., patches/0001-pr-16598-fix-bug.patch
```

### Patch Naming

Patches are automatically named using the format:
```
NNNN-pr-{PR_NUMBER}-{title}.patch
```

Where `NNNN` is a 4-digit sequence number based on the count of existing patches, and `{title}` is a sanitized version of the PR title.

## Conflict Resolution

### How rerere Works

The script uses Git's `rerere` (Reuse Recorded Resolution) feature to automatically resolve conflicts that have been seen before. When a conflict is resolved manually, rerere records the resolution. On subsequent applications of the same patch, rerere can automatically apply the recorded resolution.

The `.rr-cache/` directory stores this recorded resolution data and is committed to the repository so that all contributors benefit from previously resolved conflicts.

### Conflict Handling Flow

1. When a patch conflict occurs, the script first attempts resolution via rerere
2. If rerere cannot resolve it automatically:
   - **Interactive mode**: The script pauses and waits for you to resolve the conflicts manually in another terminal. After resolving, press Enter to continue.
   - **Non-interactive mode (CI)**: The script exits with code 2 and lists the conflicted files

### Resolving Conflicts Manually

If you need to resolve conflicts manually:

1. The script will display the conflicted files
2. Edit each file to resolve the conflicts (look for `<<<<<<<`, `=======`, `>>>>>>>` markers)
3. After resolving, stage the files:
   ```bash
   git add -u
   ```
4. The script will continue automatically

## Adding and Removing Patches

### Adding Patches

1. **Using create-patch.sh** (recommended):
   ```bash
   ./create-patch.sh https://github.com/anomalyco/opencode/pull/16598
   ```

2. **Manual addition**: Place any `.patch` file in the `patches/` directory. The filename should follow the naming convention for consistency.

### Patch Ordering

Patches are applied in alphanumeric order. To control the order, use the numeric prefix in filenames (e.g., `0001-`, `0002-`). The script sorts patches alphanumerically before applying.

### Removing Patches

Simply delete the patch file from the `patches/` directory:
```bash
rm patches/0001-pr-12345-example.patch
```

## CI Usage

For continuous integration environments, ensure the following:

1. Set the `OPENCODE_TAG` environment variable
2. The script runs in non-interactive mode (stdin is not a TTY)
3. If conflicts occur that cannot be auto-resolved, the script exits with code 2

Example CI configuration:

```bash
# In your CI pipeline
export OPENCODE_TAG=v0.1.0
./apply.sh

# Check exit code
if [[ $? -eq 0 ]]; then
  echo "Patches applied successfully"
  # Use the patched OpenCode from ./opencode/
fi
```

## rerere Cache

The `.rr-cache/` directory contains Git's recorded conflict resolutions. This directory should be committed to the repository because:

- It allows all contributors to benefit from previously resolved conflicts
- It speeds up patch application when the same conflicts recur
- It enables automatic conflict resolution in CI without manual intervention

The cache is copied to `.git/rr-cache/` in the cloned repository before patches are applied, and any new resolutions are copied back after patching completes.
