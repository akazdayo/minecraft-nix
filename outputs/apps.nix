{
  packages,
  systems,
  lib,
}:

lib.genAttrs systems (system: {
  minecraft-locker = {
    type = "app";
    program = "${packages.${system}.minecraft-locker}/bin/minecraft-locker";
  };
  default = {
    type = "app";
    program = "${packages.${system}.minecraft-locker}/bin/minecraft-locker";
  };
})
