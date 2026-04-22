#!/usr/bin/env python3

import argparse
import base64
import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


USER_AGENT = "nix-mc/minecraft-locker"
MINECRAFT_MANIFEST_URL = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
PAPER_API = "https://api.papermc.io/v2"
FABRIC_META = "https://meta.fabricmc.net/v2"
MODRINTH_API = "https://api.modrinth.com/v2"
CURSEFORGE_API = "https://api.curseforge.com/v1"
CURSEFORGE_MINECRAFT_GAME_ID = 432


class LockerError(Exception):
    pass


def request_json(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    try:
      with urllib.request.urlopen(req) as response:
          return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
      body = error.read().decode("utf-8", errors="replace")
      raise LockerError(f"GET {url} failed: HTTP {error.code}: {body}") from error
    except urllib.error.URLError as error:
      raise LockerError(f"GET {url} failed: {error.reason}") from error


def download(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
      with urllib.request.urlopen(req) as response:
          final_url = response.geturl()
          body = response.read()
          return final_url, body
    except urllib.error.HTTPError as error:
      raise LockerError(f"download {url} failed: HTTP {error.code}") from error
    except urllib.error.URLError as error:
      raise LockerError(f"download {url} failed: {error.reason}") from error


def sri_sha256(body):
    digest = hashlib.sha256(body).digest()
    return "sha256-" + base64.b64encode(digest).decode("ascii")


def filename_from_url(url, fallback):
    path = urllib.parse.urlparse(url).path
    name = Path(path).name
    return name or fallback


def artifact(ref, url, filename):
    final_url, body = download(url)
    return {
        "ref": ref,
        "url": final_url,
        "hash": sri_sha256(body),
        "filename": filename or filename_from_url(final_url, "artifact.jar"),
    }


def server_ref(software):
    server_type = software.get("type", "vanilla")
    version = required(software, "minecraftVersion", "software.minecraftVersion")
    if server_type == "paper":
        build = software.get("paper", {}).get("build")
        return f"server:paper:{version}:{build if build is not None else 'latest'}"
    if server_type == "fabric":
        fabric = software.get("fabric", {})
        loader = fabric.get("loaderVersion") or "latest"
        launcher = fabric.get("launcherVersion") or "latest"
        return f"server:fabric:{version}:{loader}:{launcher}"
    if server_type == "vanilla":
        return f"server:vanilla:{version}"
    raise LockerError(f"unsupported server type: {server_type}")


def modrinth_ref(item):
    loader = item.get("loader") or "auto"
    version = item.get("version") or "latest"
    release_type = item.get("releaseType", "release")
    optional = "true" if item.get("optional", False) else "false"
    return f"modrinth:{loader}:{required(item, 'project', 'modrinth.project')}:{version}:{release_type}:{optional}"


def curseforge_ref(item):
    return f"curseforge:{required(item, 'project', 'curseforge.project')}:{required(item, 'fileId', 'curseforge.fileId')}"


def required(obj, key, label):
    value = obj.get(key)
    if value is None or value == "":
        raise LockerError(f"missing required field: {label}")
    return value


def resolve_vanilla_server(software):
    version = required(software, "minecraftVersion", "software.minecraftVersion")
    manifest = request_json(MINECRAFT_MANIFEST_URL)
    version_entry = next((v for v in manifest["versions"] if v["id"] == version), None)
    if version_entry is None:
        raise LockerError(f"Minecraft version not found in Mojang manifest: {version}")
    version_manifest = request_json(version_entry["url"])
    server = version_manifest["downloads"]["server"]
    return artifact(f"server:vanilla:{version}", server["url"], f"minecraft-server-{version}.jar")


def resolve_paper_server(software):
    version = required(software, "minecraftVersion", "software.minecraftVersion")
    build = software.get("paper", {}).get("build")
    if build is None:
        builds = request_json(f"{PAPER_API}/projects/paper/versions/{version}/builds")["builds"]
        candidates = [b for b in builds if b.get("channel") == "default"] or builds
        if not candidates:
            raise LockerError(f"No Paper builds found for Minecraft {version}")
        build = candidates[-1]["build"]
        software.setdefault("paper", {})["build"] = build
    filename = f"paper-{version}-{build}.jar"
    url = f"{PAPER_API}/projects/paper/versions/{version}/builds/{build}/downloads/{filename}"
    return artifact(f"server:paper:{version}:{build}", url, filename)


def latest_fabric_loader(minecraft_version):
    loaders = request_json(f"{FABRIC_META}/versions/loader/{minecraft_version}")
    if not loaders:
        raise LockerError(f"No Fabric loader versions found for Minecraft {minecraft_version}")
    return loaders[0]["loader"]["version"]


def latest_fabric_installer():
    installers = request_json(f"{FABRIC_META}/versions/installer")
    stable = [i for i in installers if i.get("stable")]
    selected = (stable or installers)[0]
    return selected["version"]


def resolve_fabric_server(software):
    version = required(software, "minecraftVersion", "software.minecraftVersion")
    fabric = software.setdefault("fabric", {})
    loader = fabric.get("loaderVersion") or latest_fabric_loader(version)
    launcher = fabric.get("launcherVersion") or latest_fabric_installer()
    fabric["loaderVersion"] = loader
    fabric["launcherVersion"] = launcher
    url = f"{FABRIC_META}/versions/loader/{version}/{loader}/{launcher}/server/jar"
    filename = f"fabric-server-{version}-{loader}-{launcher}.jar"
    return artifact(f"server:fabric:{version}:{loader}:{launcher}", url, filename)


def resolve_server(software):
    server_type = software.get("type", "vanilla")
    if server_type == "vanilla":
        return resolve_vanilla_server(software)
    if server_type == "paper":
        return resolve_paper_server(software)
    if server_type == "fabric":
        return resolve_fabric_server(software)
    raise LockerError(f"unsupported server type: {server_type}")


def allowed_release_types(max_type):
    if max_type == "release":
        return {"release"}
    if max_type == "beta":
        return {"release", "beta"}
    if max_type == "alpha":
        return {"release", "beta", "alpha"}
    raise LockerError(f"invalid Modrinth releaseType: {max_type}")


def resolve_modrinth(item, software):
    ref = modrinth_ref(item)
    project = required(item, "project", "modrinth.project")
    wanted_version = item.get("version")
    release_type = item.get("releaseType", "release")
    loader = item.get("loader")
    if loader is None and software.get("type") in {"fabric", "paper"}:
        loader = software.get("type")

    if wanted_version:
        try:
            version = request_json(f"{MODRINTH_API}/version/{urllib.parse.quote(wanted_version)}")
        except LockerError:
            versions = request_json(f"{MODRINTH_API}/project/{urllib.parse.quote(project)}/version")
            version = next(
                (
                    v
                    for v in versions
                    if v.get("id") == wanted_version or v.get("version_number") == wanted_version
                ),
                None,
            )
            if version is None:
                raise LockerError(f"Modrinth version not found for {project}: {wanted_version}")
    else:
        params = {
            "game_versions": json.dumps([required(software, "minecraftVersion", "software.minecraftVersion")]),
        }
        if loader and loader != "vanilla":
            params["loaders"] = json.dumps([loader])
        query = urllib.parse.urlencode(params)
        versions = request_json(f"{MODRINTH_API}/project/{urllib.parse.quote(project)}/version?{query}")
        accepted = allowed_release_types(release_type)
        version = next((v for v in versions if v.get("version_type") in accepted), None)
        if version is None:
            if item.get("optional", False):
                return None
            raise LockerError(f"No compatible Modrinth version found for {project}")

    files = version.get("files", [])
    primary = next((f for f in files if f.get("primary")), None) or (files[0] if files else None)
    if primary is None:
        raise LockerError(f"Modrinth version has no downloadable files: {project}")
    return artifact(ref, primary["url"], primary.get("filename"))


def curseforge_headers(api_key):
    if not api_key:
        raise LockerError("CurseForge resolution requires CF_API_KEY or --curseforge-api-key")
    return {"x-api-key": api_key}


def curseforge_project_id(project, api_key):
    if isinstance(project, int) or str(project).isdigit():
        return int(project)
    params = urllib.parse.urlencode(
        {
            "gameId": CURSEFORGE_MINECRAFT_GAME_ID,
            "slug": str(project),
        }
    )
    response = request_json(f"{CURSEFORGE_API}/mods/search?{params}", curseforge_headers(api_key))
    data = response.get("data", [])
    if not data:
        raise LockerError(f"CurseForge project slug not found: {project}")
    return data[0]["id"]


def resolve_curseforge(item, api_key):
    ref = curseforge_ref(item)
    project_id = curseforge_project_id(required(item, "project", "curseforge.project"), api_key)
    file_id = required(item, "fileId", "curseforge.fileId")
    response = request_json(
        f"{CURSEFORGE_API}/mods/{project_id}/files/{file_id}",
        curseforge_headers(api_key),
    )
    data = response["data"]
    url = data.get("downloadUrl")
    if not url:
        raise LockerError(
            f"CurseForge file {project_id}:{file_id} has no API download URL; download it manually and use urls[]"
        )
    return artifact(ref, url, data.get("fileName"))


def iter_content(instance):
    for section in ("mods", "plugins", "datapacks"):
        content = instance.get(section, {})
        for item in content.get("modrinth", []):
            yield "modrinth", item
        for item in content.get("curseforge", []):
            yield "curseforge", item
        for item in content.get("urls", []):
            yield "url", item


def resolve_instance(name, instance, api_key):
    software = instance.setdefault("software", {})
    artifacts = [resolve_server(software)]
    for kind, item in iter_content(instance):
        if kind == "modrinth":
            resolved = resolve_modrinth(item, software)
            if resolved is not None:
                artifacts.append(resolved)
        elif kind == "curseforge":
            artifacts.append(resolve_curseforge(item, api_key))
        elif kind == "url":
            url = required(item, "url", "urls.url")
            hash_value = item.get("hash")
            filename = item.get("filename") or filename_from_url(url, "artifact.jar")
            if hash_value:
                artifacts.append({"ref": f"url:{url}", "url": url, "hash": hash_value, "filename": filename})
            else:
                artifacts.append(artifact(f"url:{url}", url, filename))
    return {"artifacts": artifacts}


def load_manifest(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path, value):
    body = json.dumps(value, indent=2, sort_keys=True)
    if path == "-":
        print(body)
    else:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(body + "\n")


def command_update(args):
    manifest = load_manifest(args.manifest)
    api_key = args.curseforge_api_key or os.environ.get("CF_API_KEY")
    instances = manifest.get("instances")
    if not isinstance(instances, dict) or not instances:
        raise LockerError("manifest must contain a non-empty 'instances' object")
    lock = {
        "version": 1,
        "instances": {
            name: resolve_instance(name, instance, api_key)
            for name, instance in instances.items()
        },
    }
    write_json(args.output, lock)


def build_parser():
    parser = argparse.ArgumentParser(description="Resolve Minecraft artifacts into a Nix lock file")
    subcommands = parser.add_subparsers(dest="command", required=True)

    update = subcommands.add_parser("update", help="update or create a lock file from a JSON manifest")
    update.add_argument("manifest", help="manifest JSON path")
    update.add_argument("-o", "--output", default="minecraft-lock.json", help="output lock path, or '-'")
    update.add_argument("--curseforge-api-key", help="CurseForge API key; defaults to CF_API_KEY")
    update.set_defaults(func=command_update)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.func(args)
    except LockerError as error:
        print(f"minecraft-locker: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
