# Development

## Prerequisites

- Nim 2.2.10+ with Nimble.
- `cliprompts >= 0.1.2` (installed by Nimble).
- OpenSSL development headers, because networking uses `std/httpclient` with SSL.

## Build and run

```sh
nimble install -d          # dependencies only
nimble build -d:release    # -> bin/RedstoneServerAssembler
nimble myRun               # debug build, runs from src/
```

`config.nims` adds `switch("define", "ssl")`, so a plain `nim c` also works:

```sh
nim c -d:release -o:bin/RedstoneServerAssembler src/RedstoneServerAssembler.nim
```

If you compile the sources outside this repository (or copy a module into another
project), pass `-d:ssl` yourself or HTTP requests will fail.

For quick experiments, build to a scratch path instead of touching `bin/`:

```sh
nim c -d:ssl -o:/tmp/rsa src/RedstoneServerAssembler.nim
```

## Source layout

```
src/
  RedstoneServerAssembler.nim   entrypoint and dispatch
  rsa/
    cli.nim                     flags + usage text
    flow.nim                    selection, prompts, install orchestration
    loaderstore.nim             registry and user directories
    meta.nim                    name/version/description constants
    model.nim                   types, JSON parsing, defaults
    preconfig.nim               server.properties, eula.txt, start.sh
    scenario.nim                step executor
    util.nim                    HTTP, templating, JSON, transforms, sorting
    versionfetch.nim            version APIs
loaders/
  fabric.json neoforge.json forge.json   embedded built-in definitions
docs/
  architecture.md scenario-engine.md version-sources.md development.md
```

### Conventions

- Two-space indentation, `std/[a, b]` imports, engine modules imported as
  `./[model, util]`.
- User-facing failures go through `util.fail` (`RsaError`); only the entrypoint
  prints them and chooses an exit code.
- Exported procs carry a short `##` doc comment when intent is not obvious.
- The engine must not branch on a loader id. Loader differences belong in JSON,
  or in a generic transform/step if they are truly reusable.

## Adding a built-in loader

1. Create `loaders/<id>.json` following the schema in the
   [README](../README.md#loader-format).
2. Add it to `src/rsa/loaderstore.nim`:

   ```nim
   const BuiltinMyServer = staticRead("../../loaders/myserver.json")
   ...
   result.addLoader(BuiltinMyServer, "<builtin:myserver>")
   ```

   `staticRead` paths are relative to `loaderstore.nim`.
3. Rebuild and check:

   ```sh
   bin/RedstoneServerAssembler --list-loaders
   bin/RedstoneServerAssembler --list-versions --loader myserver
   bin/RedstoneServerAssembler --list-versions --loader myserver --mc-version 1.21.1
   ```

4. Do a real non-interactive install into a throwaway directory and start the
   server once.

A loader that only a few users need can stay a user file and does not have to be
embedded.

## Extending the engine

### New scenario step

1. Add the kind to `StepKind` in `model.nim`.
2. Map the JSON `type` string in `parseStep`, including a sensible default for
   every field.
3. Read the fields in the step object (`url`, `file`, `content`, …) — add new
   fields to `ScenarioStep` if needed.
4. Implement execution in `scenario.nim`:

   - expand templates first;
   - validate required inputs with `fail`;
   - respect `optional` if the step can fail non-fatally;
   - report progress with `cliprompts` (`info`, `success`, `hint`).

5. Document the step in `README.md` and `docs/scenario-engine.md`.

### New version source kind

1. Extend `VersionSourceKind` and `parseVersionSource` (`json`, `maven`,
   `maven-xml`, `mojang` are the existing values).
2. Implement raw extraction in `versionfetch.nim` and branch in `fetchVersions`.
3. Keep extraction separate from filtering: prefix, exclude, strip and derive are
   applied uniformly afterwards.
4. Add the source to `docs/version-sources.md`.

### New transform

1. Extend `TransformKind` and `parseTransform` in `util.nim`.
2. Implement it in `applyTransform`; keep it pure and side-effect free.
3. Document it in the transforms table in `README.md`.

Transforms are the preferred way to support a loader whose version numbering
differs from Minecraft's, because they keep the engine loader-agnostic.

## Testing

There is no automated test suite yet. The `test/` directory is ignored and is
used for real server installations. The manual checklist for a change:

```sh
nim c -d:ssl -o:/tmp/rsa src/RedstoneServerAssembler.nim

/tmp/rsa --help
/tmp/rsa --version
/tmp/rsa --list-loaders
/tmp/rsa --list-versions --loader fabric
/tmp/rsa --list-versions --loader neoforge --mc-version 1.21.1
/tmp/rsa --list-versions --loader forge --mc-version 26.3
```

Then install Fabric non-interactively into a scratch directory and verify
`server.properties`, `eula.txt`, `start.sh` and file permissions:

```sh
rm -rf /tmp/srv-check
/tmp/rsa -n --loader fabric --mc-version 1.21.1 --dir /tmp/srv-check \
  --port 25570 --motd "Test" --online-mode false
cat /tmp/srv-check/server.properties
ls -l /tmp/srv-check/start.sh
```

For NeoForge and Forge, a full install downloads a large library tree; at minimum
verify the installer URL with a `HEAD` request and run one real installation
before releasing.

Custom-loader overrides can be tested without touching the config directory:

```sh
mkdir -p /tmp/loaders
cp loaders/fabric.json /tmp/loaders/mine.json
sed -i 's/"id": "fabric"/"id": "mine"/' /tmp/loaders/mine.json
RSA_LOADERS=/tmp/loaders /tmp/rsa --list-loaders
```

## Release checklist

1. Bump the version in **both** places — they are independent:
   - `RedstoneServerAssembler.nimble` (`version`),
   - `src/rsa/meta.nim` (`Version`, printed by `--version`).
2. Update `README.md` if flags, defaults, or the loader schema changed.
3. Update `docs/` for engine changes.
4. Run the manual checklist above.
5. Commit, tag (`vX.Y.Z`), push.

`bin/` is a build artifact and is ignored by git; do not commit binaries.

## Platform notes

- The generated `start.sh` assumes a POSIX shell and `cd "$(dirname "$0")"`.
- Path separation for `RSA_LOADERS` uses `os.PathSep` (`:` on Linux/macOS).
- Windows is not a target: script permissions and `sh` semantics are not
  implemented for it.