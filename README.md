# OpenCode Patches

This repo contains patches for [OpenCode](https://github.com/anomalyco/opencode) — either use my patches, or add your own.

## Use My Patches

```bash
# Clone and apply patches to latest version
./apply.sh

# Or specify a version
OPENCODE_TAG=v1.2.9 ./apply.sh

# Build the patched binary
./build.sh
```

Find your built binary at `dist/opencode-*/bin/opencode`.

## Add Your Own Patches

```bash
# Fetch any GitHub PR as a patch
./create-patch.sh https://github.com/anomalyco/opencode/pull/13719

# Patches are applied in filename order (0001-, 0002-, etc.)
# Edit the patch file if needed before applying
```

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
