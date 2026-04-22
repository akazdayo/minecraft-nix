# Repository Guidelines

## Project Structure & Module Organization

This repository is a Nix flake for reproducible Minecraft servers. Keep each Nix file focused on the value it exports.

- `flake.nix` wires the public outputs together.
- `modules/default.nix` exports the NixOS module entry point.
- `modules/minecraft-servers.nix` contains the service options and systemd implementation.
- `outputs/packages.nix`, `outputs/apps.nix`, and `outputs/checks.nix` define flake packages, apps, and checks.
- `pkgs/minecraft-locker/` contains the Python `minecraft-locker` CLI package.
- `examples/manifest.json` is the sample lock manifest used in documentation and manual testing.

## Build, Test, and Development Commands

- `nix flake check` evaluates all flake checks for supported systems.
- `nix build .#minecraft-locker` builds the Python locker package.
- `nix run .#minecraft-locker -- update examples/manifest.json -o minecraft-lock.json` resolves a manifest into a lock file.
- `nix flake show` reviews exported modules, packages, apps, and checks.

CurseForge resolution requires `CF_API_KEY` in the environment.

## Coding Style & Naming Conventions

Use two-space indentation in Nix files and keep `let` bindings small, named after the value they represent. Module option names should match the public configuration path under `services.minecraft-servers.<name>`.

Python code in `minecraft-locker.py` uses standard-library modules only, `snake_case` function names, uppercase constants, and explicit `LockerError` failures for user-facing errors. Keep generated artifact refs stable, for example `server:fabric:<mc>:<loader>:<launcher>` and `modrinth:<loader>:<project>:<version>:<releaseType>:<optional>`.

## Testing Guidelines

Add NixOS module behavior checks in `outputs/checks.nix`. Prefer small `pkgs.runCommand` assertions that inspect generated systemd configuration or scripts. Use `serverPackage = pkgs.writeText "server.jar" ""` for module tests so checks do not download Minecraft artifacts.

Run `nix flake check` before submitting changes. For locker changes that touch network resolvers, also run `nix run .#minecraft-locker -- update ...` against a minimal manifest.

## Commit & Pull Request Guidelines

Recent history uses short imperative or descriptive commit subjects, sometimes in Japanese. Keep subjects concise and scoped, for example `Use lock artifacts for direct URL content`.

Pull requests should include a summary of behavior changes, test results such as `nix flake check`, and any compatibility notes for lock file refs or NixOS options. Include example config updates when changing user-facing module options.
