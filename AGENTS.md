# AGENTS.md

Guidance for coding agents working in this repository.

## Scope

This repository contains a single Nix flake that packages the `omp` binary for multiple systems and exposes:

- `packages.<system>.default`
- `apps.<system>.default`
- `homeManagerModules.default`

## Expectations for changes

- Keep changes minimal and focused.
- Prefer updating `flake.nix` directly; avoid introducing extra files unless needed.
- When updating upstream `oh-my-pi` version, update **all** platform URLs and hashes consistently.
- Preserve system coverage (`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`) unless explicitly asked otherwise.
- Keep `meta.mainProgram = "omp"` and install path as `$out/bin/omp` unless the task requires a change.

## Validation

Primary validation command:

```bash
nix flake check
```

If the environment does not have `nix` installed, note that validation could not be executed.

## Documentation

When behavior or usage changes, update `README.md` in the same change.
