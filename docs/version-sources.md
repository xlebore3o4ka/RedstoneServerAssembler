# Version sources

`src/rsa/versionfetch.nim` implements version discovery. A `VersionSource` (see
`model.nim`) is parsed from JSON and passed to `fetchVersions(source, mc)`, which
returns a deduplicated, newest-first `seq[string]`.

## Pipeline

```
url ← expand(source.url, {mc})
raw ← extract(source.kind, url, source)
raw ← filter stable (json only)
raw ← filter prefix  (source.prefix or source.prefixFromMc)
raw ← drop exclude regex matches
raw ← strip prefix (optional)
raw ← apply deriveMc transform (optional)
result ← dedupe → sort newest-first
```

All filtering uses the untouched raw version string. `deriveMc` runs last, so
`exclude` patterns and `prefix` see what the upstream API actually publishes.

## Extraction per kind

### `json`

- Fetches the URL, parses JSON, resolves `arrayPath`.
  An empty `arrayPath` means the document itself must be an array.
- Iterates items:
  - `stablePath` (when set) is resolved with `jsonPath`. A missing node,
    `null`, or an object/array makes the item unstable.
    Boolean nodes contribute their own value; string nodes are compared to
    `stableValue`; integer nodes are stringified and compared to `stableValue`.
  - `versionPath` (default `version`) is resolved. Strings and integers are
    accepted; other kinds are skipped.
- Empty version strings are dropped.

`jsonPath` splits on `.`; numeric segments index into arrays. A missing key or an
out-of-range index yields `nil`.

### `maven`

Expects `{"versions": ["…", …]}` and takes the strings in order. This is the
shape returned by the NeoForge Maven API
(`https://maven.neoforged.net/api/maven/versions/releases/...`).

`arrayPath` is not used for this kind.

### `maven-xml`

Fetches a classic `maven-metadata.xml`, parses it with `std/xmlparser` and
collects the text of every `<version>` element (using `innerText`, because a
matching node is an element, not a text node). Forge publishes this format at
`https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml`.

`versionPath`, `arrayPath` and stability fields are not used.

### `mojang`

Fetches the Mojang manifest and walks `versions`, keeping entries whose `type` is
in `releaseTypes` (default `["release"]`). The version is the manifest `id`.

## Prefixes and transforms

`prefixFor` chooses, in order:

1. `prefix`, expanded with `{mc}`;
2. `applyTransform(mc, prefixFromMc)` when the transform is set;
3. the empty string.

When a prefix is present, only versions starting with it survive. With
`stripPrefix: true` the prefix is then removed. This is how Forge turns
`1.21.1-52.1.21` into loader version `52.1.21` while listing only versions for
the selected Minecraft version.

`Transform` supports two generic modes:

- `regex` — PCRE search and replace of the first match. Capture groups are
  1-based (`$1`…`$9`). **Nim's `re.find` stores captures starting at index 0 of
  the captures array**, so the engine reads `m[i-1]` for `$i`. A capture group
  that did not participate falls back to `defaults["$i"]` (default empty).
- `neoforge-mc` / `neoforge-prefix` — heuristics for NeoForge's artifact naming
  scheme (described below).

Unknown transform types are ignored (`tkNone`), which keeps older definitions
loadable.

## NeoForge naming heuristics

NeoForge has used two schemes:

| Minecraft | NeoForge artifact |
| --- | --- |
| `1.20.6` | `20.6.5` |
| `1.21.1` | `21.1.267` |
| `26.3` | `26.3.0.115` |
| `26.1.2` | `26.1.2.129` |

`neoforge-mc` converts an artifact version to Minecraft:

- fewer than two numeric components → unchanged;
- first component `>= 25` → year scheme: keep the first component, append the
  second and third components when non-zero (`26.3.0.115` → `26.3`,
  `26.1.2.129` → `26.1.2`);
- otherwise legacy scheme: prefix `1.`, append the second component when
  non-zero (`21.1.267` → `1.21.1`, `20.6.5` → `1.20.6`).

`neoforge-prefix` performs the inverse for filtering:

- `1.x[.y]` → `x.y.` (`1.21.1` → `21.1.`, `1.21` → `21.0.`);
- two components → `<mc>.0.` (`26.3` → `26.3.0.`);
- three or more components → `<mc>.` (`26.1.2` → `26.1.2.`).

Both are deliberately narrow: they encode a naming rule, not project-specific
data, so any loader can use them.

## Ordering

`sortVersionsDesc` splits each version on spaces and `.`, `-`, `_`, `+`, then
compares component by component:

- two numeric components compare as integers;
- numeric beats non-numeric;
- otherwise components compare as strings;
- if all common components are equal, the longer version is newer.

This makes `1.21.10` newer than `1.21.9` and keeps pre-releases after releases
with the same numeric prefix. Ordering is not SemVer-aware.

`dedupe` preserves the first occurrence before sorting.

## Built-in sources

| Loader | `gameVersions` | `loaderVersions` | `installerVersions` |
| --- | --- | --- | --- |
| Fabric | Mojang manifest (`release`) | `meta.fabricmc.net/v2/versions/loader/{mc}` | `meta.fabricmc.net/v2/versions/installer` |
| NeoForge | NeoForge Maven API, `deriveMc = neoforge-mc`, excludes `-(beta\|alpha)\|+` | same API, prefix from `neoforge-prefix`, same exclusions | — |
| Forge | Forge `maven-metadata.xml`, `deriveMc = regex ^([^-]+)-.*$` | same XML, prefix `{mc}-`, stripped, excludes `-beta$` | — |

Fabric deliberately does not filter `loaderVersions` by the `stable` flag: the
Fabric Meta API marks only the newest loader as stable, which would hide all older
versions. Sorting already puts the newest first, so the default remains the
latest release.

## Cost and caching

Every call performs network I/O; nothing is cached between runs or between
`--list-versions` and an installation. The Forge XML is a few hundred kilobytes
and is parsed in full. This is intentional for a CLI that runs once per server,
and keeps version data correct without cache invalidation logic.