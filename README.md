# OpenCode Patches

A utility repository for setting up patch management for  [OpenCode](https://github.com/anomalyco/opencode). You can use it patch in unmerged PRs from the community and build your own local version of opencode.

## Tools

### Pull a patch from GH
```bash
# Fetch any GitHub PR as a patch
./create-patch.sh https://github.com/anomalyco/opencode/pull/13719

# Patches are applied in filename order (0001-, 0002-, etc.)
# Edit the patch file if needed before applying
```

## Add Your Own Patches
```bash
# Fetch any GitHub PR as a patch
./create-patch.sh https://github.com/anomalyco/opencode/pull/13719

# Patches are applied in filename order (0001-, 0002-, etc.)
# Edit the patch file if needed before applying
```

### Apply Patches and Build Patched OpenCode
Find your built binary at `dist/opencode-*/bin/opencode`.

## Scripts

| Script | Purpose |
|--------|---------|
| `apply.sh` | Clone OpenCode and apply all patches in `patches/` |
| `create-patch.sh` | Fetch a GitHub PR as a `.patch` file |
| `build.sh` | Build patched OpenCode into a binary |

## Configuration

Set the OpenCode version via:
- Environment variable: `OPENCODE_TAG=v1.2.9 ./apply.sh`
- `.env` file: `OPENCODE_TAG=v1.2.9`
- Interactive prompt (if neither is set)

Run `./apply.sh --help` for more options.

