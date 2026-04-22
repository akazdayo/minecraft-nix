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
  }
)
