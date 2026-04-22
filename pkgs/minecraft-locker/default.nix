{
  lib,
  python3,
}:

python3.pkgs.buildPythonApplication {
  pname = "minecraft-locker";
  version = "0.1.0";
  pyproject = false;

  src = ./.;

  installPhase = ''
    runHook preInstall
    install -Dm755 minecraft-locker.py "$out/bin/minecraft-locker"
    runHook postInstall
  '';

  meta = {
    description = "Resolve Minecraft server and mod artifacts into a reproducible Nix lock file";
    license = lib.licenses.mit;
    mainProgram = "minecraft-locker";
    platforms = lib.platforms.linux;
  };
}
