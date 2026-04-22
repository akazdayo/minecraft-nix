{
  nixpkgs,
  module,
  systems,
}:

nixpkgs.lib.genAttrs systems (
  system:
  let
    pkgs = import nixpkgs { inherit system; };
    machine = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        module
        (
          { pkgs, ... }:
          {
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "tmpfs";
              fsType = "tmpfs";
            };
            system.stateVersion = "25.11";

            services.minecraft-servers.smoke = {
              enable = true;
              eula = true;
              software = {
                type = "vanilla";
                minecraftVersion = "1.21.4";
                serverPackage = pkgs.writeText "server.jar" "";
              };
              serverProperties = {
                motd = "Nix smoke test";
                difficulty = "easy";
              };
              jvm.memory = "512M";
            };
          }
        )
      ];
    };
    optionalMissingLockMachine = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        module
        (
          { pkgs, ... }:
          {
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "tmpfs";
              fsType = "tmpfs";
            };
            system.stateVersion = "25.11";

            services.minecraft-servers.optional-mod = {
              enable = true;
              eula = true;
              lockFile = builtins.toFile "minecraft-lock.json" (
                builtins.toJSON {
                  version = 1;
                  instances.optional-mod.artifacts = [ ];
                }
              );
              software = {
                type = "fabric";
                minecraftVersion = "1.21.4";
                serverPackage = pkgs.writeText "server.jar" "";
                fabric = {
                  loaderVersion = "0.16.10";
                  launcherVersion = "1.0.1";
                };
              };
              mods.modrinth = [
                {
                  project = "missing-optional";
                  optional = true;
                }
              ];
            };
          }
        )
      ];
    };
    directUrlLockMachine = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        module
        (
          { pkgs, ... }:
          {
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "tmpfs";
              fsType = "tmpfs";
            };
            system.stateVersion = "25.11";

            services.minecraft-servers.direct-url-lock = {
              enable = true;
              eula = true;
              lockFile = builtins.toFile "minecraft-lock.json" (
                builtins.toJSON {
                  version = 1;
                  instances.direct-url-lock.artifacts = [
                    {
                      ref = "url:file:///dev/null";
                      url = "file:///dev/null";
                      hash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=";
                      filename = "direct-url-artifact.jar";
                    }
                  ];
                }
              );
              software = {
                type = "vanilla";
                minecraftVersion = "1.21.4";
                serverPackage = pkgs.writeText "server.jar" "";
              };
              mods.urls = [
                {
                  url = "file:///dev/null";
                }
              ];
            };
          }
        )
      ];
    };
  in
  {
    module-smoke = pkgs.runCommand "minecraft-module-smoke" {
      serviceDescription = machine.config.systemd.services.minecraft-server-smoke.description;
    } ''
      test "$serviceDescription" = "Minecraft server smoke"
      touch "$out"
    '';

    module-optional-modrinth-skip = pkgs.runCommand "minecraft-module-optional-modrinth-skip" {
      preStart = optionalMissingLockMachine.config.systemd.services.minecraft-server-optional-mod.serviceConfig.ExecStartPre;
    } ''
      test -x "$preStart"
      touch "$out"
    '';

    module-empty-access-files = pkgs.runCommand "minecraft-module-empty-access-files" {
      preStart = machine.config.systemd.services.minecraft-server-smoke.serviceConfig.ExecStartPre;
    } ''
      grep -q '/whitelist.json' "$preStart"
      grep -q '/ops.json' "$preStart"
      touch "$out"
    '';

    module-direct-url-lock = pkgs.runCommand "minecraft-module-direct-url-lock" {
      preStart = directUrlLockMachine.config.systemd.services.minecraft-server-direct-url-lock.serviceConfig.ExecStartPre;
    } ''
      grep -q 'minecraft-direct-url-lock-mods' "$preStart"
      touch "$out"
    '';
  }
)
