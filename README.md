# RedstoneServerAssembler

The interactive CLI that automates Minecraft server setup — core, version, config, EULA, path, all in one dialog.

`RedstoneServerAssembler` downloads a Minecraft server with the loader of your choice,
writes a ready-to-run configuration and creates a launch script. It works either as a
guided dialogue or completely non-interactively with command-line flags.

- **Fabric, NeoForge and Forge** out of the box.
- **Any other loader or server software** can be added with a JSON definition — no
  recompilation and no engine changes.
- **Pre-configuration is actually written** to `server.properties` (the old
  `PreConfig` values used to be collected and thrown away).
- **EULA and start script** are handled for you.
- **Two modes:** an interactive dialogue and a flags-only mode for scripts and CI.

## Requirements

- Linux or macOS (the generated start script is a POSIX `sh` script).
- [Nim](https://nim-lang.org) 2.2.10 or newer and Nimble to build from source.
- Java installed and available as `java` in `PATH` when the selected loader needs
  an installer (NeoForge and Forge run the official installer, Fabric does not).
- Internet access to the version APIs and Maven repositories of the selected loader.

## Install

```sh
git clone https://github.com/xlebore3o4ka/RedstoneServerAssembler.git
cd RedstoneServerAssembler
nimble install -d
nimble build -d:release
```

The binary is created at `bin/RedstoneServerAssembler`. You can also run
`nimble install` to put it into your Nimble bin directory.

## Quick start (interactive)

Run the program without arguments:

```sh
RedstoneServerAssembler
```

It will ask, in order:

1. **Core** — the server loader (Fabric, NeoForge, Forge or a custom one).
2. **Minecraft version** — searchable list, newest first.
3. **Loader version** — searchable list; press Enter to take the newest.
4. **Installer version** — only for loaders that publish a separate installer.
5. **Pre-configure the server?** — answer `y` to go through the server settings,
   or `n` to install only the server files.
6. The server settings (port, MOTD, gamemode, difficulty, …), each with a default.
   Press Enter to keep the default.

The server is installed into the current directory. The dialogue is minimalistic:
arrow keys to move, type to search, Enter to confirm.

When it finishes you get a ready server:

```sh
cd /path/to/server
./start.sh
```

## Non-interactive mode

Add `-n` (or `--non-interactive`) to skip every question. In this mode
`--loader` and `--mc-version` are required; all other values fall back to their
defaults. Unspecified loader and installer versions resolve to the newest
available version.

```sh
# Fabric 1.21.1 into ./srv
RedstoneServerAssembler -n --loader fabric --mc-version 1.21.1 --dir srv

# NeoForge with explicit versions and custom settings
RedstoneServerAssembler -n \
  --loader neoforge \
  --mc-version 1.21.1 \
  --loader-version 21.1.267 \
  --dir /opt/mc/neoforge \
  --port 25570 \
  --motd "Private server" \
  --online-mode true \
  --max-players 8

# Install server files only, no server.properties
RedstoneServerAssembler -n --loader forge --mc-version 26.3 --dir forge-srv --no-preconfig
```

## Listing loaders and versions

```sh
# Loaders available to this installation
RedstoneServerAssembler --list-loaders

# Minecraft versions supported by a loader
RedstoneServerAssembler --list-versions --loader fabric

# Loader versions for a specific Minecraft version
RedstoneServerAssembler --list-versions --loader fabric --mc-version 1.21.1

# Installer versions are resolved automatically; use --installer-version to pin one
```

`--list-versions` prints one version per line and is safe to use in scripts.

## Command-line reference

### General

| Option | Description |
| --- | --- |
| `-h`, `--help` | Show help and exit. |
| `-v`, `--version` | Show the program version and exit. |
| `--list-loaders` | List known loaders (`id`, name, description) and exit. |
| `--list-versions` | List versions for `--loader`; with `--mc-version` lists loader versions instead of Minecraft versions. |
| `-n`, `--non-interactive` | Disable all prompts. Requires `--loader` and `--mc-version`. |

### Installation

| Option | Default | Description |
| --- | --- | --- |
| `--loader <id>` | — | Loader id, e.g. `fabric`, `neoforge`, `forge`. |
| `--mc-version <version>` | — | Minecraft version, e.g. `1.21.1`. Required with `-n`. |
| `--loader-version <version>` | newest | Loader version. |
| `--installer-version <version>` | newest | Installer version, for loaders that have one. |
| `--dir <path>` | current directory | Target directory. Created if missing. |
| `--no-preconfig` | off | Do not write `server.properties`. |
| `--preconfig` | on | Write `server.properties` (default; useful to override a previous flag). |

### Server properties

All values below are written to `server.properties` during installation. In
interactive mode they become the defaults shown in the dialogue; flags win only
when you accept the default, so you can still adjust them interactively.

| Option | Property | Default |
| --- | --- | --- |
| `--port <n>`, `--server-port <n>` | `server-port` | `25565` |
| `--ip <addr>`, `--server-ip <addr>` | `server-ip` | empty (listen on all interfaces) |
| `--max-players <n>` | `max-players` | `20` |
| `--motd <text>` | `motd` | `A RedstoneServerAssembled Minecraft Server` |
| `--online-mode [true\|false]` | `online-mode` | `false` |
| `--whitelist [true\|false]`, `--white-list [...]` | `white-list` | `false` |
| `--gamemode <mode>` | `gamemode` | `survival` |
| `--difficulty <level>` | `difficulty` | `normal` |
| `--level-name <name>` | `level-name` | `world` |
| `--view-distance <n>` | `view-distance` | `10` |
| `--simulation-distance <n>` | `simulation-distance` | `10` |
| `--spawn-protection <n>` | `spawn-protection` | `16` |
| `--op-permission-level <n>` | `op-permission-level` | `4` |
| `--generate-structures [true\|false]` | `generate-structures` | `true` |
| `--level-type <type>` | `level-type` | empty (Minecraft default) |
| `--allow-flight [true\|false]` | `allow-flight` | `false` |

Allowed gamemodes: `survival`, `creative`, `adventure`, `spectator`.
Allowed difficulties: `peaceful`, `easy`, `normal`, `hard`.

Boolean options can be written in three ways:

```sh
--online-mode            # true
--online-mode false      # explicit value
--no-online-mode         # false
```

The same `--no-…` form works for `--whitelist`, `--generate-structures` and
`--allow-flight`.

## What gets installed

After a successful run the target directory contains the server and:

| File | Description |
| --- | --- |
| loader server files | The downloaded server jar, or the `run.sh` / library tree produced by the NeoForge or Forge installer. |
| `eula.txt` | Written with `eula=true`. By using the program you agree to the [Minecraft EULA](https://aka.ms/MinecraftEULA). |
| `server.properties` | The selected settings. Omitted with `--no-preconfig`. |
| `start.sh` | A small POSIX script that `cd`s into its own directory and starts the server. |
| `user_jvm_args.txt` | NeoForge/Forge only. Created with `-Xms2G` and `-Xmx6G` if it does not already exist. |

`start.sh` is only written when the file is absent or was generated by this
program; a `start.sh` you wrote yourself is never overwritten.

If `server.properties` already exists it is merged: the keys listed above are
updated, every other key and comment is preserved.

## Custom loaders and scenarios

Loader definitions are plain JSON files. Adding a loader means dropping a file
into one of these directories — the engine needs no changes:

1. Directories listed in the `RSA_LOADERS` environment variable
   (separated by `:` on Linux/macOS).
2. `$XDG_CONFIG_HOME/redstone-server-assembler/loaders/`
   (usually `~/.config/redstone-server-assembler/loaders/`).
3. `./loaders/` next to the current working directory.

All `*.json` files in those directories are loaded in that order. Built-in
loaders are loaded first, so a user file with the same `id` overrides a built-in
loader. If two user files define the same `id`, the one loaded later wins.
Files are validated when the program starts; a broken file stops the run with
an error that names the file.

### Loader format

```json
{
  "id": "myserver",
  "name": "My Server",
  "description": "Example custom server loader.",
  "website": "https://example.com",
  "javaVersion": "21",
  "gameVersions": { "...": "see version sources" },
  "loaderVersions": { "...": "see version sources" },
  "installerVersions": { "...": "optional, see version sources" },
  "scenario": [ "...": "see scenario steps" ],
  "launch": "java -Xmx4G -jar \"{file}\" nogui"
}
```

| Field | Required | Description |
| --- | --- | --- |
| `id` | yes | Unique identifier used by `--loader`. |
| `name` | yes | Name shown in the dialogue and lists. |
| `description` | no | Shown by `--list-loaders`. |
| `website` | no | Informational URL. |
| `javaVersion` | no | Informational Java requirement, e.g. `21`. |
| `gameVersions` | yes | Where to get supported Minecraft versions. |
| `loaderVersions` | yes | Where to get loader versions for a Minecraft version. |
| `installerVersions` | no | Where to get installer versions. When omitted, the loader version is used as the installer version. |
| `scenario` | yes | Ordered list of installation steps. |
| `launch` | no | Command written to `start.sh`. When empty, no start script is created. |

### Version sources

A version source describes where versions come from and how to filter them.

```json
{
  "kind": "json",
  "url": "https://example.com/versions/{mc}.json",
  "arrayPath": "versions",
  "versionPath": "version",
  "stablePath": "stable",
  "stableValue": "true",
  "prefix": "{mc}-",
  "stripPrefix": true,
  "exclude": "-beta$",
  "deriveMc": { "type": "regex", "pattern": "^([^-]+)-.*$", "replacement": "$1" }
}
```

| Field | Default | Description |
| --- | --- | --- |
| `kind` | `json` | One of `json`, `maven`, `maven-xml`, `mojang`. |
| `url` | — | Source URL. `{mc}` is replaced with the selected Minecraft version. |
| `arrayPath` | — | Dot path to the array of version objects (`json` only). Empty means the document itself is the array. Numeric segments index arrays. |
| `versionPath` | `version` | Dot path to the version string inside each item (`json` only). |
| `stablePath` | — | Dot path to a stability flag (`json` only). When set, only matching items are kept. |
| `stableValue` | `true` | Value compared against `stablePath` for string and number nodes. Boolean nodes use their own value directly. |
| `prefix` | — | Keep only versions starting with this text. `{mc}` is expanded. |
| `prefixFromMc` | — | A transform that computes the prefix from the Minecraft version (used when `prefix` is empty). |
| `stripPrefix` | `false` | Remove the prefix from version strings after filtering. |
| `exclude` | — | Regular expression; matching versions are dropped. |
| `deriveMc` | — | A transform that turns an item into a Minecraft version. Used by `gameVersions` when the source lists loader versions. |
| `releaseTypes` | `["release"]` | Mojang manifest types to keep (`release`, `snapshot`, `old_beta`, `old_alpha`). |

Source kinds:

- **`json`** — a JSON array (or an array at `arrayPath`) of objects. Each object
  is inspected with `versionPath`, `stablePath` and `stableValue`.
- **`maven`** — a Maven repository API returning `{"versions": ["1.0", ...]}`.
- **`maven-xml`** — a classic `maven-metadata.xml`; every `<version>` is used.
- **`mojang`** — the Mojang version manifest
  (`https://piston-meta.mojang.com/mc/game/version_manifest_v2.json`).
  `releaseTypes` selects which versions are kept.

Versions are deduplicated and sorted newest-first. Numeric parts are compared
as numbers, so `1.21.10` is newer than `1.21.9`.

### Transforms

Transforms are used by `prefixFromMc` and `deriveMc`.

```json
{ "type": "regex", "pattern": "^1\\.(\\d+)(?:\\.(\\d+))?$", "replacement": "$1.$2.",
  "defaults": { "$2": "0" } }
```

| Type | Description |
| --- | --- |
| `regex` | PCRE search-and-replace of the first match. `$1`…`$9` are capture groups; a group that did not participate falls back to `defaults`. |
| `neoforge-mc` | Converts NeoForge artifact versions to Minecraft versions: `21.1.267` → `1.21.1`, `26.3.0.115` → `26.3`. |
| `neoforge-prefix` | Converts a Minecraft version to the NeoForge artifact prefix: `1.21.1` → `21.1.`, `26.3` → `26.3.0.`. |

### Scenario steps

A scenario is executed in order inside the target directory. Any step failing
aborts the installation unless it is marked `optional`.

| Type | Fields | Description |
| --- | --- | --- |
| `download` | `url`, `file` | Downloads `url` to `file`. If `file` is omitted, the file name from the URL is used. |
| `run` | `command`, `optional` | Runs a shell command and waits for it. On failure the last lines of output are shown. |
| `write` | `file`, `content`, `overwrite` | Writes a text file. `overwrite` defaults to `true`; with `false` an existing file is kept. |
| `replace` | `file`, `find`, `replace`, `onlyIfExists` | Replaces every occurrence of `find` in an existing file. Missing files are ignored when `onlyIfExists` is `true` (default). |
| `mkdir` | `file` | Creates a directory (yes, the field is named `file`). |
| `require` | `file`, `optional` | Checks that a file exists. Failing this step marks the installation as failed unless `optional` is `true`. |
| `copy` | `source`, `target`, `optional` | Copies a file. |

### Template variables

These placeholders can be used in every `url`, `file`, `command`, `content`,
`find`, `replace`, `source`, `target` and in `launch`:

| Placeholder | Value |
| --- | --- |
| `{mc}` | Selected Minecraft version. |
| `{loader}` | Selected loader version. |
| `{installer}` | Selected installer version (equals `{loader}` when the loader has no separate installer versions). |
| `{dir}` | Absolute path of the target directory. |
| `{file}` | File produced by the previous `download` step. |
| `{loaderId}` | Loader `id`. |
| `{loaderName}` | Loader `name`. |

### Complete example

A minimal custom loader using a Maven-style version API:

```json
{
  "id": "myserver",
  "name": "My Server",
  "description": "Example custom server loader.",
  "website": "https://example.com",
  "javaVersion": "21",
  "gameVersions": {
    "kind": "mojang",
    "url": "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json",
    "releaseTypes": ["release"]
  },
  "loaderVersions": {
    "kind": "maven",
    "url": "https://maven.example.com/api/versions/releases/com/example/myserver",
    "exclude": "-beta$",
    "prefix": "{mc}-",
    "stripPrefix": true
  },
  "scenario": [
    {
      "type": "download",
      "url": "https://maven.example.com/releases/com/example/myserver/{loader}/myserver-{loader}.jar",
      "file": "server.jar"
    },
    {
      "type": "write",
      "file": "server.properties",
      "overwrite": false,
      "content": "motd=Hello from My Server\n"
    }
  ],
  "launch": "java -Xmx4G -jar \"{file}\" nogui"
}
```

Real definitions you can copy and adapt live in `loaders/fabric.json`,
`loaders/neoforge.json` and `loaders/forge.json`.

### Tips for new loaders

- Prefer a `download` of a ready-to-run jar when the project publishes one.
- For an installer-based loader, use a `download` step, then
  `run` with `--installServer`, then `require` the generated start script.
- Use `write` with `"overwrite": false` for user-editable files such as
  `user_jvm_args.txt`.
- Test with `--list-versions --loader <id>` before installing: it exercises the
  version APIs without touching the disk.

## Troubleshooting

- **`unknown loader '<id>'`** — the id is not in `--list-loaders`. Check
  `$RSA_LOADERS`, `~/.config/redstone-server-assembler/loaders/` and `./loaders/`.
- **`no versions available`** — the version source returned nothing after
  filtering. Check `prefix`, `stablePath`, `releaseTypes` and `exclude`, and try
  `--list-versions --loader <id>`.
- **Installer step fails** — make sure `java` is installed and recent enough for
  the selected Minecraft version (newer versions require Java 21).
- **`start.sh already exists and was left untouched`** — remove or rename the
  existing script if you want the generated one.
- **Download or network errors** — the program prints the failing URL; check
  connectivity and proxy settings.

## License

LGPL-3.0-only. See [LICENSE](LICENSE).