---
name: minecraft-nix
description: |
  Configure reproducible Minecraft servers on NixOS with the akazdayo/minecraft-nix flake.

  Use when adding the minecraft-nix flake to a NixOS configuration, writing server manifests,
  generating minecraft-lock.json with minecraft-locker, configuring services.minecraft-servers,
  or debugging lock artifact, systemd service, mod/plugin/datapack, EULA, firewall, RCON,
  Fabric, Paper, Vanilla, or NeoForge setup issues.
---

# minecraft-nix

Use this skill to help users run reproducible Minecraft servers with the `akazdayo/minecraft-nix` Nix flake.

## Core Model

`minecraft-nix` has two coordinated inputs:

- A JSON manifest for `minecraft-locker`, which resolves server jars and content artifacts into `minecraft-lock.json`.
- A NixOS module config under `services.minecraft-servers.<name>`, which declares the same server software and content and fetches artifacts from the lock file.

Keep the manifest and NixOS module in sync. The lock file stores artifacts by stable refs, and the module reconstructs those refs from the declared options.

## Standard Workflow

1. Add the flake input:

```nix
inputs.minecraft-nix.url = "github:akazdayo/minecraft-nix";
```

2. Import the module:

```nix
{
  imports = [ minecraft-nix.nixosModules.default ];
}
```

3. Create or update a manifest:

```json
{
  "instances": {
    "survival": {
      "software": {
        "type": "fabric",
        "minecraftVersion": "1.21.4",
        "fabric": {
          "loaderVersion": null,
          "launcherVersion": null
        }
      },
      "mods": {
        "modrinth": [
          {
            "project": "fabric-api",
            "version": null,
            "loader": null,
            "releaseType": "release",
            "optional": false
          }
        ],
        "curseforge": [],
        "urls": []
      },
      "plugins": {
        "modrinth": [],
        "curseforge": [],
        "urls": []
      },
      "datapacks": {
        "modrinth": [],
        "curseforge": [],
        "urls": []
      }
    }
  }
}
```

4. Generate the lock file:

```sh
nix run github:akazdayo/minecraft-nix#minecraft-locker -- update manifest.json -o minecraft-lock.json
```

For a local checkout of this repository, use:

```sh
nix run .#minecraft-locker -- update examples/manifest.json -o minecraft-lock.json
```

CurseForge resolution requires:

```sh
CF_API_KEY=... nix run github:akazdayo/minecraft-nix#minecraft-locker -- update manifest.json -o minecraft-lock.json
```

5. Copy resolved version fields from the manifest/lock result into the NixOS config when they were `null`.

Fabric requires `software.fabric.loaderVersion` and `software.fabric.launcherVersion`.
Paper requires `software.paper.build`.
NeoForge requires `software.neoforge.version`.

6. Configure the server:

```nix
services.minecraft-servers.survival = {
  enable = true;
  eula = true;
  lockFile = ./minecraft-lock.json;

  software = {
    type = "fabric";
    minecraftVersion = "1.21.4";
    fabric = {
      loaderVersion = "0.16.10";
      launcherVersion = "1.0.1";
    };
  };

  mods.modrinth = [
    {
      project = "fabric-api";
      version = null;
      loader = null;
      releaseType = "release";
      optional = false;
    }
  ];

  port = 25565;
  openFirewall = true;
  jvm.memory = "4G";
  serverProperties.motd = "NixOS Minecraft";
};
```

7. Rebuild and inspect the service:

```sh
sudo nixos-rebuild switch
sudo systemctl status minecraft-server-survival
```

## Server Software

Supported `software.type` values:

- `vanilla`: requires `minecraftVersion`.
- `fabric`: requires `minecraftVersion`, `fabric.loaderVersion`, and `fabric.launcherVersion` in the final NixOS config.
- `paper`: requires `minecraftVersion` and `paper.build` in the final NixOS config.
- `neoforge`: requires `minecraftVersion` and `neoforge.version` in the final NixOS config.

For tests or a local custom jar, set `software.serverPackage` instead of `lockFile`.

## Content Sources

The `mods`, `plugins`, and `datapacks` options share the same shape:

```nix
{
  modrinth = [
    {
      project = "fabric-api";
      version = null;
      loader = null;
      releaseType = "release";
      optional = false;
    }
  ];
  curseforge = [
    {
      project = "some-project-slug-or-id";
      fileId = 1234567;
    }
  ];
  urls = [
    {
      url = "https://example.com/file.jar";
      hash = null;
      filename = "file.jar";
    }
  ];
}
```

Use `urls[].hash = null` when the locker should download the file and write the SRI hash to `minecraft-lock.json`. Use a non-null hash when the direct URL is already hash-pinned and does not need the lock file for that artifact.

## Operational Options

Common module options:

- `eula = true` is mandatory for enabled servers.
- `port` sets the main TCP port and defaults to `25565`.
- `openFirewall = true` opens `port`, and also opens `rcon.port` when RCON is enabled.
- `jvm.memory = "4G"` sets both `-Xms` and `-Xmx`; use `jvm.initialMemory` and `jvm.maxMemory` for separate values.
- `serverProperties` renders sorted `server.properties` entries.
- `ops` and `whitelist` render `ops.json` and `whitelist.json`.
- `extraFiles` symlinks additional files or directories into the server state directory.
- `rcon.enable`, `rcon.port`, and `rcon.passwordFile` configure RCON. Put the password in a file, not inline in Nix.

Systemd service names are `minecraft-server-<instanceName>`. Persistent data lives under `/var/lib/minecraft-servers/<instanceName>`.

## Debugging

For missing lock artifact errors, compare the module declaration with the manifest that produced `minecraft-lock.json`. The instance name and every content entry must match because refs are generated from the option values.

Typical refs:

- `server:vanilla:<minecraftVersion>`
- `server:fabric:<minecraftVersion>:<loaderVersion>:<launcherVersion>`
- `server:paper:<minecraftVersion>:<build>`
- `server:neoforge:<minecraftVersion>:<neoforgeVersion>`
- `modrinth:<loader-or-auto>:<project>:<version-or-latest>:<releaseType>:<optional>`
- `curseforge:<project>:<fileId>`
- `url:<url>`

For assertion failures after running the locker, fill in the resolved Fabric loader/launcher, Paper build, or NeoForge version in the NixOS config. The final module config must not leave these version fields as `null`.

For CurseForge failures, check `CF_API_KEY` or pass `--curseforge-api-key`. CurseForge file IDs are required; latest CurseForge resolution is intentionally not supported.

For NeoForge, the service runs the installer before startup when the expected `unix_args.txt` is missing or the recorded NeoForge version changed.

## Validation

Prefer these checks after changes:

```sh
nix flake check
nix build .#minecraft-locker
nix run .#minecraft-locker -- update examples/manifest.json -o minecraft-lock.json
```

When editing this repository, add NixOS module behavior checks in `outputs/checks.nix`. Use `serverPackage = pkgs.writeText "server.jar" ""` in module tests to avoid downloading Minecraft artifacts.
