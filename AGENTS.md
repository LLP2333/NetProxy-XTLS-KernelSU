# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

NetProxy-Magisk is an Android Magisk/KernelSU/APatch transparent proxy module based on Xray-core. The repo has two developable parts:

1. **VitePress documentation site** (`docs/`) — the main buildable/runnable artifact in this environment.
2. **Android module shell scripts** (`src/module/`) — designed to run on Android; can be linted with `shellcheck` but not executed here.

### Running the docs dev server

```sh
cd docs && npm run dev
```

The dev server starts on `http://localhost:5173/` with `--host` flag (accessible on all interfaces).

### Building docs

```sh
cd docs && npm run build
```

Output goes to `docs/.vitepress/dist`.

### Linting shell scripts

```sh
shellcheck src/module/*.sh src/module/scripts/core/*.sh src/module/scripts/network/*.sh src/module/scripts/utils/*.sh src/module/scripts/cli
```

Use `-x` flag if you want shellcheck to follow sourced files. Existing warnings (SC2034, SC3043, SC2155, etc.) are pre-existing in the codebase.

### Key notes

- The CI (`.github/workflows/docs.yml`) uses **Node 24** and `npm ci` for the docs site.
- The CI (`.github/workflows/build.yml`) packages the module with `7z` — no compilation step.
- `package-lock.json` is the lockfile; use `npm ci` (not `npm install`) for reproducible installs.
- The `tools/proxylink` git submodule is referenced in `.gitmodules` but not required for docs or script linting.
