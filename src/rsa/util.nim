import std/[os, strutils, json, httpclient, tables, algorithm, re, sequtils]

type
  RsaError* = object of CatchableError
    ## Fatal, user-facing error raised by any part of the assembler.

const
  UserAgent* = "RedstoneServerAssembler"

proc fail*(message: string) {.noreturn.} =
  raise newException(RsaError, message)

proc httpGet*(url: string, timeout = 120_000, attempts = 3): string =
  ## Downloads `url` into memory. Raises RsaError on any failure.
  var lastError = ""
  for attempt in 1 .. attempts:
    let client = newHttpClient(userAgent = UserAgent, timeout = timeout)
    try:
      return client.getContent(url)
    except CatchableError as e:
      lastError = e.msg
      if attempt < attempts:
        sleep(400 * attempt)
    finally:
      client.close()
  fail("failed to download " & url & ": " & lastError)

proc downloadTo*(url, path: string, timeout = 600_000, attempts = 3) =
  ## Streams `url` to `path`, removing a partially written file on failure.
  var lastError = ""
  for attempt in 1 .. attempts:
    let client = newHttpClient(userAgent = UserAgent, timeout = timeout)
    try:
      writeFile(path, client.getContent(url))
      return
    except CatchableError as e:
      lastError = e.msg
      if fileExists(path):
        removeFile(path)
      if attempt < attempts:
        sleep(400 * attempt)
    finally:
      client.close()
  fail("failed to download " & url & ": " & lastError)

proc expand*(text: string, vars: openArray[(string, string)]): string =
  ## Replaces every `{key}` in `text` with its value.
  result = text
  for (key, value) in vars:
    result = result.replace("{" & key & "}", value)

# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------

proc strOf*(node: JsonNode, key: string, default = ""): string =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JString:
    node[key].getStr()
  else:
    default

proc boolOf*(node: JsonNode, key: string, default = false): bool =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JBool:
    node[key].getBool()
  else:
    default

proc intOf*(node: JsonNode, key: string, default = 0): int =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JInt:
    node[key].getInt()
  else:
    default

proc arrayOf*(node: JsonNode, key: string): JsonNode =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JArray:
    node[key]
  else:
    newJArray()

proc jsonPath*(node: JsonNode, path: string): JsonNode =
  ## Resolves a dot separated path (`loader.version`). An empty path returns the
  ## node itself. Numeric segments index into arrays.
  result = node
  if path.len == 0:
    return
  for part in path.split('.'):
    if result.isNil:
      return nil
    if result.kind == JArray:
      try:
        let index = parseInt(part)
        if index < 0 or index >= result.len:
          return nil
        result = result[index]
      except ValueError:
        return nil
    elif result.kind == JObject:
      if not result.hasKey(part):
        return nil
      result = result[part]
    else:
      return nil

# ---------------------------------------------------------------------------
# Transforms
# ---------------------------------------------------------------------------

type
  TransformKind* = enum
    tkNone
    tkRegex
    tkNeoForgeMc
    tkNeoForgePrefix

  Transform* = object
    kind*: TransformKind
    pattern*: string
    replacement*: string
    defaults*: Table[string, string]

proc parseTransform*(node: JsonNode): Transform =
  if node.isNil or node.kind != JObject:
    return Transform(kind: tkNone)
  let kind = node.strOf("type", "none").toLowerAscii()
  case kind
  of "regex":
    result.kind = tkRegex
    result.pattern = node.strOf("pattern")
    result.replacement = node.strOf("replacement")
    if node.hasKey("defaults") and node["defaults"].kind == JObject:
      for key, value in node["defaults"]:
        if value.kind == JString:
          result.defaults[key] = value.getStr()
  of "neoforge-mc", "neoforgemc":
    result.kind = tkNeoForgeMc
  of "neoforge-prefix", "neoforgeprefix":
    result.kind = tkNeoForgePrefix
  else:
    discard

proc applyRegex(value: string, t: Transform): string =
  var m: array[9, string]
  if find(value, re(t.pattern), m) < 0:
    return value
  result = t.replacement
  for i in 1 .. 9:
    let captured =
      if m[i - 1].len > 0: m[i - 1]
      else: t.defaults.getOrDefault("$" & $i, "")
    result = result.replace("$" & $i, captured)

proc isNumeric(value: string): bool =
  value.len > 0 and value.allCharsInSet({'0'..'9'})

proc neoforgeMcOf(value: string): string =
  ## NeoForge 21.1.267 -> 1.21.1, 26.3.0.115 -> 26.3.
  let parts = value.split('.')
  if parts.len < 2 or not isNumeric(parts[0]) or not isNumeric(parts[1]):
    return value
  if parseInt(parts[0]) >= 25:
    result = parts[0]
    if parts[1] != "0":
      result.add "." & parts[1]
      if parts.len >= 3 and isNumeric(parts[2]) and parts[2] != "0":
        result.add "." & parts[2]
  else:
    result = "1." & parts[0]
    if parts[1] != "0":
      result.add "." & parts[1]

proc neoforgePrefixOf(mc: string): string =
  ## 1.21.1 -> 21.1., 1.21 -> 21.0., 26.3 -> 26.3.0., 26.1.2 -> 26.1.2.
  if mc.startsWith("1."):
    let parts = mc[2 .. ^1].split('.')
    if parts.len >= 2 and isNumeric(parts[0]) and isNumeric(parts[1]):
      result = parts[0] & "." & parts[1] & "."
    elif parts.len == 1 and isNumeric(parts[0]):
      result = parts[0] & ".0."
  elif mc.len > 0:
    let parts = mc.split('.')
    if parts.len == 2:
      result = mc & ".0."
    elif parts.len >= 3:
      result = mc & "."

proc applyTransform*(value: string, t: Transform): string =
  case t.kind
  of tkNone:
    result = value
  of tkRegex:
    result = applyRegex(value, t)
  of tkNeoForgeMc:
    result = neoforgeMcOf(value)
  of tkNeoForgePrefix:
    result = neoforgePrefixOf(value)

# ---------------------------------------------------------------------------
# Version ordering
# ---------------------------------------------------------------------------

proc cmpPart(a, b: string): int =
  let aNum = a.len > 0 and a.allCharsInSet({'0'..'9'})
  let bNum = b.len > 0 and b.allCharsInSet({'0'..'9'})
  if aNum and bNum:
    let ai = parseInt(a)
    let bi = parseInt(b)
    result = cmp(ai, bi)
  elif aNum and not bNum:
    result = 1
  elif bNum and not aNum:
    result = -1
  else:
    result = cmp(a, b)

proc cmpVersions(a, b: string): int =
  let aParts = a.split({' ', '.', '-', '_', '+'}).filterIt(it.len > 0)
  let bParts = b.split({' ', '.', '-', '_', '+'}).filterIt(it.len > 0)
  let common = min(aParts.len, bParts.len)
  for i in 0 ..< common:
    result = cmpPart(aParts[i], bParts[i])
    if result != 0:
      return
  result = cmp(aParts.len, bParts.len)

proc sortVersionsDesc*(versions: var seq[string]) =
  versions.sort(proc(a, b: string): int = cmpVersions(b, a))

proc dedupe*(versions: seq[string]): seq[string] =
  var seen: Table[string, bool]
  for version in versions:
    if not seen.hasKey(version):
      seen[version] = true
      result.add(version)

proc fileBaseName*(path: string): string =
  result = path
  let query = result.find({'?', '#'})
  if query >= 0:
    result = result[0 ..< query]
  let slash = max(result.rfind('/'), result.rfind('\\'))
  if slash >= 0:
    result = result[slash + 1 .. ^1]
  if result.len == 0:
    result = "download"

proc withTrailingSlash*(path: string): string =
  if path.len == 0 or path[^1] in {'/', '\\'}: path else: path & '/'