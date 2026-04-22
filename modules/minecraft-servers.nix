{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatLists
    concatMapStringsSep
    escapeShellArg
    filter
    flatten
    hasAttr
    literalExpression
    mapAttrs'
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optional
    optionalAttrs
    optionalString
    types
    ;

  cfg = config.services.minecraft-servers;

  valueToString =
    value:
    if builtins.isBool value then
      lib.boolToString value
    else
      toString value;

  renderProperties =
    attrs:
    concatMapStringsSep "\n" (name: "${name}=${valueToString attrs.${name}}") (
      builtins.sort builtins.lessThan (builtins.attrNames attrs)
    )
    + "\n";

  lockFromFile =
    lockFile:
    if lockFile == null then
      { version = 1; instances = { }; }
    else
      builtins.fromJSON (builtins.readFile lockFile);

  artifactType = types.submodule {
    options = {
      ref = mkOption {
        type = types.str;
        description = "Stable artifact reference used in the lock file.";
      };
      url = mkOption {
        type = types.str;
        description = "Download URL for the artifact.";
      };
      hash = mkOption {
        type = types.str;
        description = "Nix SRI hash, for example sha256-....";
      };
      filename = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Filename to use when placing the artifact into the server directory.";
      };
    };
  };

  modrinthRef =
    software: entry:
    "modrinth:${if entry.loader == null then "auto" else entry.loader}:${entry.project}:${
      if entry.version == null then "latest" else entry.version
    }:${entry.releaseType}:${
      lib.boolToString entry.optional
    }";

  curseforgeRef = entry: "curseforge:${entry.project}:${toString entry.fileId}";

  serverRef =
    software:
    if software.type == "paper" then
      "server:paper:${software.minecraftVersion}:${
        if software.paper.build == null then "latest" else toString software.paper.build
      }"
    else if software.type == "fabric" then
      "server:fabric:${software.minecraftVersion}:${
        if software.fabric.loaderVersion == null then "latest" else software.fabric.loaderVersion
      }:${if software.fabric.launcherVersion == null then "latest" else software.fabric.launcherVersion}"
    else if software.type == "neoforge" then
      "server:neoforge:${software.minecraftVersion}:${
        if software.neoforge.version == null then "latest" else software.neoforge.version
      }"
    else
      "server:vanilla:${software.minecraftVersion}";

  sanitizeName =
    name:
    builtins.replaceStrings
      [
        "/"
        ":"
        "?"
        "&"
        "="
        " "
      ]
      [
        "-"
        "-"
        "-"
        "-"
        "-"
        "-"
      ]
      name;

  artifactName =
    artifact:
    if artifact.filename != null then
      artifact.filename
    else
      "${sanitizeName artifact.ref}.jar";

  fetchArtifact =
    artifact:
    pkgs.fetchurl {
      inherit (artifact) url hash;
      name = artifactName artifact;
    };

  findArtifact =
    instanceName: lock: ref:
    let
      artifacts = lock.instances.${instanceName}.artifacts or [ ];
      matches = filter (artifact: artifact.ref == ref) artifacts;
    in
    if matches == [ ] then
      throw "services.minecraft-servers.${instanceName}: missing lock artifact '${ref}'"
    else
      builtins.head matches;

  findOptionalArtifacts =
    instanceName: lock: ref:
    let
      artifacts = lock.instances.${instanceName}.artifacts or [ ];
      matches = filter (artifact: artifact.ref == ref) artifacts;
    in
    if matches == [ ] then [ ] else [ (builtins.head matches) ];

  directUrlOption = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "Direct artifact URL.";
      };
      hash = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Nix SRI hash for the URL. Null means the artifact is read from the lock file.";
      };
      filename = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Filename to use under mods/plugins/datapacks.";
      };
    };
  };

  modrinthOption = types.submodule {
    options = {
      project = mkOption {
        type = types.str;
        description = "Modrinth project slug or ID.";
      };
      version = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Modrinth version ID or version number. Null means the locker resolves the latest allowed version.";
      };
      loader = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Loader override used during lock resolution.";
      };
      releaseType = mkOption {
        type = types.enum [
          "release"
          "beta"
          "alpha"
        ];
        default = "release";
        description = "Maximum Modrinth release type accepted by the locker.";
      };
      optional = mkOption {
        type = types.bool;
        default = false;
        description = "Whether lock resolution may skip this project when no compatible file exists.";
      };
    };
  };

  curseforgeOption = types.submodule {
    options = {
      project = mkOption {
        type = types.oneOf [
          types.str
          types.int
        ];
        description = "CurseForge project slug or numeric project ID.";
      };
      fileId = mkOption {
        type = types.int;
        description = "CurseForge file ID. Latest resolution is intentionally not supported for reproducibility.";
      };
    };
  };

  contentSetOption = types.submodule {
    options = {
      modrinth = mkOption {
        type = types.listOf modrinthOption;
        default = [ ];
        description = "Modrinth artifacts to place in this content directory.";
      };
      curseforge = mkOption {
        type = types.listOf curseforgeOption;
        default = [ ];
        description = "CurseForge artifacts to place in this content directory.";
      };
      urls = mkOption {
        type = types.listOf directUrlOption;
        default = [ ];
        description = "Direct hash-pinned URLs to place in this content directory.";
      };
    };
  };

  playerOption = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Minecraft player name.";
      };
      uuid = mkOption {
        type = types.str;
        description = "Player UUID.";
      };
    };
  };

  opOption = types.submodule {
    options = playerOption.options // {
      level = mkOption {
        type = types.ints.between 1 4;
        default = 4;
        description = "Operator permission level.";
      };
      bypassesPlayerLimit = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this operator may bypass the player limit.";
      };
    };
  };

  extraFileOption = types.submodule {
    options = {
      source = mkOption {
        type = types.path;
        description = "Source file or directory copied by symlink into the server state directory.";
      };
      target = mkOption {
        type = types.str;
        example = "config/example.toml";
        description = "Target path relative to the server state directory.";
      };
    };
  };

  instanceOption = types.submodule (
    { name, config, ... }:
    {
      options = {
        enable = mkEnableOption "this Minecraft server instance";

        eula = mkOption {
          type = types.bool;
          default = false;
          description = "Set to true to accept the Minecraft EULA.";
        };

        user = mkOption {
          type = types.str;
          default = "minecraft";
          description = "User that runs the server.";
        };

        group = mkOption {
          type = types.str;
          default = "minecraft";
          description = "Group that runs the server.";
        };

        stateDir = mkOption {
          type = types.str;
          default = "/var/lib/minecraft-servers/${name}";
          readOnly = true;
          description = "Persistent state directory for this server.";
        };

        lockFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = literalExpression "./minecraft-lock.json";
          description = "JSON lock file produced by minecraft-locker.";
        };

        software = {
          type = mkOption {
            type = types.enum [
              "vanilla"
              "fabric"
              "paper"
              "neoforge"
            ];
            default = "vanilla";
            description = "Minecraft server software type.";
          };

          minecraftVersion = mkOption {
            type = types.str;
            description = "Minecraft version, for example 1.21.4.";
          };

          serverPackage = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = "Optional prebuilt server jar, or installer jar for installer-based software. When set, the server artifact is not read from the lock file.";
          };

          paper.build = mkOption {
            type = types.nullOr (types.oneOf [
              types.str
              types.int
            ]);
            default = null;
            description = "Paper build number. Null means minecraft-locker resolves and locks the latest build.";
          };

          fabric.loaderVersion = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Fabric loader version. Null means minecraft-locker resolves and locks the latest loader.";
          };

          fabric.launcherVersion = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Fabric installer/launcher version. Null means minecraft-locker resolves and locks the latest installer.";
          };

          neoforge.version = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "NeoForge version. Null means minecraft-locker resolves and locks the latest compatible version.";
          };
        };

        javaPackage = mkOption {
          type = types.package;
          default = pkgs.jre_headless;
          defaultText = literalExpression "pkgs.jre_headless";
          description = "Java runtime package used to launch the server.";
        };

        jvm = {
          memory = mkOption {
            type = types.nullOr types.str;
            default = "1G";
            description = "Sets both -Xms and -Xmx unless initialMemory or maxMemory are set.";
          };
          initialMemory = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Initial JVM heap size.";
          };
          maxMemory = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Maximum JVM heap size.";
          };
          extraArgs = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Extra JVM arguments.";
          };
        };

        extraServerArgs = mkOption {
          type = types.listOf types.str;
          default = [ "nogui" ];
          description = "Arguments passed after the server jar.";
        };

        serverProperties = mkOption {
          type = types.attrsOf (
            types.oneOf [
              types.str
              types.int
              types.bool
            ]
          );
          default = { };
          example = {
            motd = "A NixOS Minecraft Server";
            difficulty = "normal";
            "max-players" = 20;
          };
          description = "Attributes rendered into server.properties.";
        };

        mods = mkOption {
          type = contentSetOption;
          default = { };
          description = "Artifacts placed in mods/.";
        };

        plugins = mkOption {
          type = contentSetOption;
          default = { };
          description = "Artifacts placed in plugins/.";
        };

        datapacks = mkOption {
          type = contentSetOption;
          default = { };
          description = "Artifacts placed in world/datapacks/.";
        };

        extraFiles = mkOption {
          type = types.listOf extraFileOption;
          default = [ ];
          description = "Additional files or directories linked into the state directory.";
        };

        whitelist = mkOption {
          type = types.listOf playerOption;
          default = [ ];
          description = "Players rendered into whitelist.json.";
        };

        ops = mkOption {
          type = types.listOf opOption;
          default = [ ];
          description = "Operators rendered into ops.json.";
        };

        port = mkOption {
          type = types.port;
          default = 25565;
          description = "Primary TCP port, also used for firewall configuration.";
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = "Open the Minecraft TCP port in the NixOS firewall.";
        };

        rcon = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable RCON server.properties entries and firewall support.";
          };
          port = mkOption {
            type = types.port;
            default = 25575;
            description = "RCON TCP port.";
          };
          passwordFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "File containing the RCON password.";
          };
        };
      };
    }
  );

  buildContentEntries =
    instanceName: software: lock: content:
    let
      lockedArtifacts =
        concatLists (
          map (
            entry:
            let
              ref = modrinthRef software entry;
            in
            if entry.optional then
              findOptionalArtifacts instanceName lock ref
            else
              [ (findArtifact instanceName lock ref) ]
          ) content.modrinth
        )
        ++ (map (entry: findArtifact instanceName lock (curseforgeRef entry)) content.curseforge);
      directArtifacts = map (
        entry:
        let
          ref = "url:${entry.url}";
        in
        if entry.hash == null then
          findArtifact instanceName lock ref
        else
          {
            inherit ref;
            inherit (entry) url hash filename;
          }
      ) content.urls;
    in
    map (artifact: {
      name = artifactName artifact;
      path = fetchArtifact artifact;
    }) (lockedArtifacts ++ directArtifacts);

  makeLinkFarm =
    name: entries:
    if entries == [ ] then
      null
    else
      pkgs.linkFarm name entries;

  mkServer =
    name: server:
    let
      lock = lockFromFile server.lockFile;
      serverArtifact =
        if server.software.serverPackage != null then
          server.software.serverPackage
        else
          fetchArtifact (findArtifact name lock (serverRef server.software));
      neoforgeArgsFile = "libraries/net/neoforged/neoforge/${server.software.neoforge.version}/unix_args.txt";
      neoforgeInstallId = "neoforge:${server.software.minecraftVersion}:${server.software.neoforge.version}:${toString serverArtifact}";
      isNeoForge = server.software.type == "neoforge";

      baseProperties = {
        "server-port" = server.port;
        "enable-rcon" = server.rcon.enable;
        "rcon.port" = server.rcon.port;
      }
      // optionalAttrs (server.whitelist != [ ]) { "white-list" = true; };

      serverPropertiesFile = pkgs.writeText "server.properties" (
        renderProperties (baseProperties // server.serverProperties)
      );
      eulaFile = pkgs.writeText "eula.txt" ''
        eula=true
      '';
      whitelistFile = pkgs.writeText "whitelist.json" (builtins.toJSON server.whitelist);
      opsFile = pkgs.writeText "ops.json" (builtins.toJSON server.ops);

      modsFarm = makeLinkFarm "minecraft-${name}-mods" (
        buildContentEntries name server.software lock server.mods
      );
      pluginsFarm = makeLinkFarm "minecraft-${name}-plugins" (
        buildContentEntries name server.software lock server.plugins
      );
      datapacksFarm = makeLinkFarm "minecraft-${name}-datapacks" (
        buildContentEntries name server.software lock server.datapacks
      );

      heapArgs =
        optional (server.jvm.initialMemory != null || server.jvm.memory != null) "-Xms${
          if server.jvm.initialMemory != null then server.jvm.initialMemory else server.jvm.memory
        }"
        ++ optional (server.jvm.maxMemory != null || server.jvm.memory != null) "-Xmx${
          if server.jvm.maxMemory != null then server.jvm.maxMemory else server.jvm.memory
        }";

      javaArgs = heapArgs ++ server.jvm.extraArgs;
      serverArgs = server.extraServerArgs;

      syncDir =
        target: source:
        ''
          rm -rf ${escapeShellArg target}
          mkdir -p ${escapeShellArg target}
        ''
        + optionalString (source != null) ''
          find ${escapeShellArg (toString source)} -mindepth 1 -maxdepth 1 -exec ln -s {} ${escapeShellArg target}/ \;
        '';

      linkExtraFile =
        file:
        let
          target = "${server.stateDir}/${file.target}";
        in
        ''
          mkdir -p ${escapeShellArg (lib.dirOf target)}
          rm -rf ${escapeShellArg target}
          ln -s ${escapeShellArg (toString file.source)} ${escapeShellArg target}
        '';

      preStart = pkgs.writeShellScript "minecraft-${name}-pre-start" ''
        set -euo pipefail

        install -d -m 0755 ${escapeShellArg server.stateDir}
        ${
          if isNeoForge then
            ''
              marker=${escapeShellArg server.stateDir}/.minecraft-nix-neoforge-install-id
              if [ ! -f ${escapeShellArg "${server.stateDir}/${neoforgeArgsFile}"} ] || [ "$(cat "$marker" 2>/dev/null || true)" != ${escapeShellArg neoforgeInstallId} ]; then
                ${server.javaPackage}/bin/java -jar ${escapeShellArg (toString serverArtifact)} --installServer
                printf '%s\n' ${escapeShellArg neoforgeInstallId} > "$marker"
              fi
              test -f ${escapeShellArg "${server.stateDir}/${neoforgeArgsFile}"}
            ''
          else
            ''
              ln -sfn ${escapeShellArg (toString serverArtifact)} ${escapeShellArg server.stateDir}/server.jar
            ''
        }
        cp ${serverPropertiesFile} ${escapeShellArg server.stateDir}/server.properties
        cp ${eulaFile} ${escapeShellArg server.stateDir}/eula.txt
        cp ${whitelistFile} ${escapeShellArg server.stateDir}/whitelist.json
        cp ${opsFile} ${escapeShellArg server.stateDir}/ops.json
        ${syncDir "${server.stateDir}/mods" modsFarm}
        ${syncDir "${server.stateDir}/plugins" pluginsFarm}
        ${syncDir "${server.stateDir}/world/datapacks" datapacksFarm}
        ${concatMapStringsSep "\n" linkExtraFile server.extraFiles}

        ${optionalString (server.rcon.enable && server.rcon.passwordFile != null) ''
          password="$(tr -d '\r\n' < ${escapeShellArg (toString server.rcon.passwordFile)})"
          tmp="$(${pkgs.coreutils}/bin/mktemp)"
          ${pkgs.gnugrep}/bin/grep -v '^rcon.password=' ${escapeShellArg server.stateDir}/server.properties > "$tmp" || true
          printf 'rcon.password=%s\n' "$password" >> "$tmp"
          mv "$tmp" ${escapeShellArg server.stateDir}/server.properties
        ''}
      '';
    in
    {
      assertions = [
        {
          assertion = server.eula;
          message = "services.minecraft-servers.${name}.eula must be true to accept the Minecraft EULA.";
        }
        {
          assertion = server.software.serverPackage != null || server.lockFile != null;
          message = "services.minecraft-servers.${name} needs either software.serverPackage or lockFile.";
        }
        {
          assertion = server.software.type != "paper" || server.software.paper.build != null;
          message = "services.minecraft-servers.${name}.software.paper.build must be set after running minecraft-locker.";
        }
        {
          assertion =
            server.software.type != "fabric"
            || (server.software.fabric.loaderVersion != null && server.software.fabric.launcherVersion != null);
          message = "services.minecraft-servers.${name}.software.fabric.loaderVersion and launcherVersion must be set after running minecraft-locker.";
        }
        {
          assertion = server.software.type != "neoforge" || server.software.neoforge.version != null;
          message = "services.minecraft-servers.${name}.software.neoforge.version must be set after running minecraft-locker.";
        }
      ];

      systemd.services."minecraft-server-${name}" = {
        description = "Minecraft server ${name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.coreutils
          pkgs.findutils
        ];
        serviceConfig = {
          Type = "simple";
          User = server.user;
          Group = server.group;
          WorkingDirectory = server.stateDir;
          StateDirectory = "minecraft-servers/${name}";
          StateDirectoryMode = "0755";
          Restart = "on-failure";
          RestartSec = "10s";
          ExecStartPre = preStart;
          ExecStart =
            if isNeoForge then
              "${server.javaPackage}/bin/java ${lib.escapeShellArgs javaArgs} @${neoforgeArgsFile} ${lib.escapeShellArgs serverArgs}"
            else
              "${server.javaPackage}/bin/java ${lib.escapeShellArgs javaArgs} -jar server.jar ${lib.escapeShellArgs serverArgs}";
        };
      };

      networking.firewall.allowedTCPPorts =
        optional server.openFirewall server.port
        ++ optional (server.openFirewall && server.rcon.enable) server.rcon.port;
    };
in
{
  options.services.minecraft-servers = mkOption {
    type = types.attrsOf instanceOption;
    default = { };
    description = "Declarative Minecraft server instances.";
  };

  config = {
    users.groups.minecraft = { };
    users.users.minecraft = {
      isSystemUser = true;
      group = "minecraft";
      home = "/var/lib/minecraft-servers";
      createHome = true;
    };

    assertions = flatten (
      lib.mapAttrsToList (
        name: server:
        if server.enable then
          (mkServer name server).assertions
        else
          [ ]
      ) cfg
    );

    systemd.services = mapAttrs' (
      name: server:
      nameValuePair "minecraft-server-${name}" (
        mkIf server.enable (mkServer name server).systemd.services."minecraft-server-${name}"
      )
    ) cfg;

    networking.firewall.allowedTCPPorts = concatLists (
      lib.mapAttrsToList (
        name: server:
        if server.enable then
          (mkServer name server).networking.firewall.allowedTCPPorts
        else
          [ ]
      ) cfg
    );
  };
}
