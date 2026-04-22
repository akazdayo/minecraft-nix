{
  nixpkgs,
  systems,
}:

nixpkgs.lib.genAttrs systems (
  system:
  let
    pkgs = import nixpkgs { inherit system; };
  in
  {
    minecraft-locker = pkgs.callPackage ../pkgs/minecraft-locker { };
    default = pkgs.callPackage ../pkgs/minecraft-locker { };
  }
)
