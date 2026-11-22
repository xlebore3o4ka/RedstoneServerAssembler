import std/[json, os, strutils, tables, algorithm, sequtils]
import ./[model, util]

const
  BuiltinFabric = staticRead("../../loaders/fabric.json")
  BuiltinNeoForge = staticRead("../../loaders/neoforge.json")
  BuiltinForge = staticRead("../../loaders/forge.json")

type
  LoaderRegistry* = object
    ids*: seq[string]
    defs*: Table[string, LoaderDef]

proc addLoader(registry: var LoaderRegistry, content, origin: string) =
  var node: JsonNode
  try:
    node = parseJson(content)
  except JsonParsingError as e:
    fail("cannot parse loader definition " & origin & ": " & e.msg)
  let loader = parseLoader(node)
  if not registry.defs.hasKey(loader.id):
    registry.ids.add(loader.id)
  registry.defs[loader.id] = loader

proc addFile(registry: var LoaderRegistry, path: string) =
  try:
    registry.addLoader(readFile(path), path)
  except IOError as e:
    fail("cannot read loader definition " & path & ": " & e.msg)

proc configLoaderDir*(): string =
  getConfigDir() / "redstone-server-assembler" / "loaders"

proc loaderDirs*(): seq[string] =
  ## Directories scanned for user loader definitions, in override order.
  result = @[]
  let envDirs = getEnv("RSA_LOADERS")
  if envDirs.len > 0:
    for dir in envDirs.split(PathSep):
      if dir.len > 0:
        result.add(dir)
  result.add(configLoaderDir())
  result.add(getCurrentDir() / "loaders")

proc loadRegistry*(): LoaderRegistry =
  ## Loads embedded loaders, then overrides them with user definitions.
  result.addLoader(BuiltinFabric, "<builtin:fabric>")
  result.addLoader(BuiltinNeoForge, "<builtin:neoforge>")
  result.addLoader(BuiltinForge, "<builtin:forge>")

  for dir in loaderDirs():
    if not dirExists(dir):
      continue
    var files = toSeq(walkFiles(dir / "*.json"))
    files.sort()
    for path in files:
      result.addFile(path)

  let defs = result.defs
  result.ids.sort(proc(a, b: string): int =
    cmp(defs[a].name, defs[b].name))

proc getLoader*(registry: LoaderRegistry, id: string): LoaderDef =
  if not registry.defs.hasKey(id):
    fail("unknown loader '" & id & "'. Available: " & registry.ids.join(", "))
  result = registry.defs[id]

proc hasLoader*(registry: LoaderRegistry, id: string): bool =
  registry.defs.hasKey(id)