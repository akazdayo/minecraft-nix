{
  description = "NixOS modules and lock tooling for reproducible Minecraft servers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      module = import ./modules;
      packages = import ./outputs/packages.nix {
        inherit nixpkgs systems;
      };
    in
    {
      nixosModules = {
        default = module;
        minecraft-servers = module;
      };

      inherit packages;

      apps = import ./outputs/apps.nix {
        inherit packages systems lib;
      };

      checks = import ./outputs/checks.nix {
        inherit nixpkgs module systems;
      };
    };
}
