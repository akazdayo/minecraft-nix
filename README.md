# minecraft-nix

NixOS module and lock tooling for reproducible Minecraft servers.

The module runs Minecraft directly under systemd. It does not run
`itzg/docker-minecraft-server`, but its option model borrows the useful parts:
server type selection, `server.properties` management, and declarative
mods/plugins/datapacks.

## Quick start

1. Add this flake to your NixOS configuration:

   ```nix
   inputs.minecraft-nix.url = "github:akazdayo/minecraft-nix";
   ```

2. Create a manifest for the server and mods you want to lock:

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
             { "project": "fabric-api", "version": null }
           ]
         }
       }
     }
   }
   ```

3. Generate the lock file:

   ```sh
   nix run github:akazdayo/minecraft-nix#minecraft-locker -- update manifest.json -o minecraft-lock.json
   ```

4. Use the module in your NixOS config:

   ```nix
   {
     imports = [ minecraft-nix.nixosModules.default ];

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
         { project = "fabric-api"; }
       ];

       port = 25565;
       openFirewall = true;
       jvm.memory = "4G";
       serverProperties.motd = "NixOS Minecraft";
     };
   }
   ```

5. Rebuild NixOS and start the service:

   ```sh
   sudo nixos-rebuild switch
   sudo systemctl status minecraft-server-survival
   ```

## Layout

Each Nix file has one job and returns one kind of value:

- `flake.nix`: flake output aggregation only
- `modules/default.nix`: the exported NixOS module
- `modules/minecraft-servers.nix`: Minecraft server module implementation
- `outputs/packages.nix`: flake `packages`
- `outputs/apps.nix`: flake `apps`
- `outputs/checks.nix`: flake `checks`
- `pkgs/minecraft-locker/default.nix`: `minecraft-locker` package

## Basic NixOS usage

```nix
{
  inputs.minecraft-nix.url = "github:akazdayo/minecraft-nix";

  outputs =
    { nixpkgs, minecraft-nix, ... }:
    {
      nixosConfigurations.host = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          minecraft-nix.nixosModules.default
          {
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

              port = 25565;
              openFirewall = true;
              jvm.memory = "4G";

              serverProperties = {
                motd = "NixOS Minecraft";
                difficulty = "normal";
                "max-players" = 20;
              };

              mods.modrinth = [
                {
                  project = "fabric-api";
                  version = null;
                }
              ];
            };
          }
        ];
      };
    };
}
```

For a local custom jar or tests, set `software.serverPackage` instead of
`lockFile`.

## Lock files

Use the locker to resolve server jars and mods into URL plus Nix SRI hashes:

```sh
nix run .#minecraft-locker -- update examples/manifest.json -o minecraft-lock.json
```

CurseForge needs an API key when resolving `curseforge` entries:

```sh
CF_API_KEY=... nix run .#minecraft-locker -- update manifest.json -o minecraft-lock.json
```

The lock file contains per-instance artifacts. The NixOS module looks up each
declared server/mod/plugin/datapack by its stable `ref`, fetches it with
`pkgs.fetchurl`, and links it into the instance state directory.

## Supported v1 scope

- Server software: Vanilla, Fabric, Paper
- Artifact sources: server lock entries, Modrinth, CurseForge file IDs, direct URLs
- Runtime: NixOS systemd service
- Managed directories: `mods/`, `plugins/`, `world/datapacks/`
- Generated files: `eula.txt`, `server.properties`, `ops.json`, `whitelist.json`

Forge, NeoForge, Quilt, Purpur, modpack manifests, and automatic latest-at-startup
updates are intentionally left out of v1.
