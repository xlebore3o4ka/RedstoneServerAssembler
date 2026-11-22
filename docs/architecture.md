# Architecture

This document describes how RedstoneServerAssembler is put together. User-facing
documentation lives in the top-level [README](../README.md).

## Goals

- Adding a loader or a download scenario must not require changes to the engine.
- Installation is declarative: a loader describes *what* to fetch and run, the
  engine decides *how*.
- The interactive and non-interactive modes share the same installation path and
  the same configuration writer.

## Module map

All engine code lives in `src/rsa/`; `src/RedstoneServerAssembler.nim` is a thin
entrypoint.

| Module | Responsibility |
| --- | --- |
| `meta.nim` | Program name, version, description, author, EULA URL. |
| `cli.nim` | Flag parsing and the help text. |
| `model.nim` | Core types, JSON parsing for loader definitions and steps, validation, defaults for `ServerConfig` and `CliOptions`. |
| `util.nim` | Networking, templating, JSON path/field helpers, transforms, version comparison, small filesystem helpers, `RsaError`. |
| `versionfetch.nim` | Fetching and filtering versions from the four source kinds. |
| `loaderstore.nim` | The loader registry: embedded built-ins plus user overrides. |
| `scenario.nim` | Executor for declarative scenario steps. |
| `preconfig.nim` | `server.properties` merge writer, `eula.txt`, `start.sh`. |
| `flow.nim` | Selection (interactive and from flags), pre-configuration prompts, installation orchestration. |
| `RedstoneServerAssembler.nim` | Entrypoint: parse flags, build registry, dispatch to lists/help or installation, map exceptions to exit codes. |

## Data flow

```
main
 ├─ parseCli(argv)                     -> CliOptions
 ├─ loadRegistry()                     -> LoaderRegistry
 │   ├─ built-in JSON (staticRead)
 │   └─ user JSON files (RSA_LOADERS, config dir, ./loaders)
 ├─ mode dispatch
 │   ├─ --help / --version
 │   ├─ --list-loaders
 │   ├─ --list-versions
 │   └─ install
 │       ├─ chooseInteractive()  (dialogue)   ─┐
 │       └─ selectionFromCli()   (-n)           ├─> Selection
 │       ├─ promptPreconfig()    (interactive)  │
 │       └─ opts.config          (-n)           ┘
 │       └─ install(selection, dir, doPreconfig, config)
 │           ├─ runScenario()
 │           ├─ writeEula()
 │           ├─ writeServerProperties()  (unless --no-preconfig)
 │           └─ writeStartScript()
 └─ exception handling + terminal restore
```

### Error handling

Every expected failure raises `RsaError` through `util.fail`. The entrypoint
catches it, prints the message with the `cliprompts` error style and exits with
status 1. Unexpected `CatchableError`s are reported as `unexpected error: …`.
`restoreTerminalState()` runs in a `finally` block so the cursor is restored even
after an exception.

Notably, `loaderstore` validates every definition while loading, so a broken user
file aborts the run before anything is downloaded.

## Registry and extensibility

Built-in definitions are compiled into the binary:

```nim
const BuiltinFabric = staticRead("../../loaders/fabric.json")
```

`staticRead` is resolved relative to `src/rsa/loaderstore.nim`, i.e. the paths are
`<project>/loaders/*.json`. Adding a built-in loader therefore means adding a JSON
file and one `const` + `addLoader` call.

User directories are scanned afterwards in this order:

1. each entry of `RSA_LOADERS` (path separator separated),
2. `getConfigDir() / "redstone-server-assembler" / "loaders"`,
3. `getCurrentDir() / "loaders"`.

Within a directory files are sorted by name. Registration is
"last definition wins": `defs[id] = loader`, while `ids` only grows when an id is
seen for the first time. This gives user files precedence over built-ins and a
stable display order (sorted by `name` at the end of `loadRegistry`).

`LoaderDef` is an ordinary value object; the engine never branches on a loader id.
The only loader-specific knowledge is expressed in JSON through transforms and
scenario steps.

## Installation transaction

`flow.install` does the following:

1. `createDir(targetDir)` (idempotent).
2. Resolve `vars.dir` to an absolute path.
3. `setCurrentDir(vars.dir)`, with a `try/finally` that restores the previous
   directory on every exit path.
4. Run the loader scenario.
5. Write `eula.txt`.
6. Optionally merge `server.properties`.
7. Expand `launch` and write `start.sh`.

`InstallVars` carries the template variables. The `file` field is mutable: each
`download` step updates it so later steps can refer to the last downloaded file,
which is what most loader definitions need.

There is deliberately no rollback of partially downloaded files. A failed step
leaves the directory as-is for inspection, and re-running the tool is safe for
downloads (files are overwritten) and for `write` steps with
`"overwrite": false`.

## Pre-configuration

`ServerConfig` is a typed record. `preconfig.properties` is the single place that
maps it to `server.properties` keys; both the interactive dialogue and the flag
parser fill the same record (`CliOptions.config`).

The writer reads an existing `server.properties`, updates only the keys produced
by `properties()` and appends missing ones. Comments and unknown keys survive.
`server-ip` and `level-type` are omitted when empty so the server keeps its own
defaults.

`eula.txt` follows the same merge approach. `start.sh` is only overwritten when it
is missing or contains the `# Generated by RedstoneServerAssembler` marker, which
protects hand-written scripts.

## Networking

`util.httpGet` / `util.downloadTo` create a fresh `std/httpclient` client per
request with a fixed user agent and generous timeouts. Failed transfers are
retried up to three times with a short linear backoff, which smooths over
transient DNS/IPv6/socket failures against the version APIs. Downloads are
buffered in memory before writing; this is acceptable for server jars and Maven
metadata but is the first thing to change if very large artifacts are ever
fetched directly by the engine. Partially written files are removed on failure.

## Known limitations

- No HTTP caching or conditional requests.
- No parallel downloads; steps run strictly in order.
- `run` steps inherit the process environment and use the system shell; there is
  no sandboxing.
- The `javaVersion` loader field is informational; Java compatibility is not
  checked at runtime.
- Windows is not supported by the generated `start.sh` workflow.