import std/[json, re, strutils, xmltree, xmlparser]
import ./[model, util]

proc fetchJson(url: string): JsonNode =
  let content = httpGet(url)
  try:
    result = parseJson(content)
  except JsonParsingError as e:
    fail("invalid JSON from " & url & ": " & e.msg)

proc isStable(item: JsonNode, src: VersionSource): bool =
  if src.stablePath.len == 0:
    return true
  let node = jsonPath(item, src.stablePath)
  if node.isNil:
    return false
  case node.kind
  of JBool:
    result = node.getBool()
  of JString:
    result = node.getStr() == src.stableValue
  of JInt:
    result = $node.getInt() == src.stableValue
  else:
    result = false

proc rawJsonVersions(src: VersionSource, mc: string): seq[string] =
  let url = expand(src.url, {"mc": mc})
  var items = jsonPath(fetchJson(url), src.arrayPath)
  if items.isNil or items.kind != JArray:
    fail("expected a JSON array at '" & src.arrayPath & "' in " & url)
  for item in items:
    if not isStable(item, src):
      continue
    let versionNode = jsonPath(item, src.versionPath)
    if versionNode.isNil:
      continue
    let version =
      case versionNode.kind
      of JString: versionNode.getStr()
      of JInt: $versionNode.getInt()
      else: ""
    if version.len > 0:
      result.add(version)

proc rawMavenJsonVersions(url: string): seq[string] =
  let root = fetchJson(url)
  for item in root.arrayOf("versions"):
    if item.kind == JString:
      result.add(item.getStr())

proc rawMavenXmlVersions(url: string): seq[string] =
  let content = httpGet(url)
  var root: XmlNode
  try:
    root = parseXml(content)
  except XmlError as e:
    fail("invalid XML from " & url & ": " & e.msg)
  for node in root.findAll("version"):
    let text = node.innerText.strip()
    if text.len > 0:
      result.add(text)

proc rawMojangVersions(src: VersionSource, url: string): seq[string] =
  let root = fetchJson(url)
  let allowed = src.releaseTypes
  for item in root.arrayOf("versions"):
    let kind = item.strOf("type")
    if kind in allowed:
      let id = item.strOf("id")
      if id.len > 0:
        result.add(id)

proc prefixFor(src: VersionSource, mc: string): string =
  if src.prefixTemplate.len > 0:
    result = expand(src.prefixTemplate, {"mc": mc})
  elif src.prefixFromMc.kind != tkNone:
    result = applyTransform(mc, src.prefixFromMc)

proc fetchVersions*(src: VersionSource, mc = ""): seq[string] =
  ## Returns stable versions of a source, newest first. For game version
  ## sources (`mc` empty) `deriveMc` converts loader versions into MC versions.
  if src.url.len == 0:
    return @[]

  let url = expand(src.url, {"mc": mc})
  var raw: seq[string]
  case src.kind
  of vsJson:
    raw = rawJsonVersions(src, mc)
  of vsMavenJson:
    raw = rawMavenJsonVersions(url)
  of vsMavenXml:
    raw = rawMavenXmlVersions(url)
  of vsMojang:
    raw = rawMojangVersions(src, url)

  let prefix = src.prefixFor(mc)
  for version in raw:
    if prefix.len > 0:
      if not version.startsWith(prefix):
        continue
    if src.excludePattern.len > 0 and version.contains(re(src.excludePattern)):
      continue
    var value = version
    if prefix.len > 0 and src.stripPrefix:
      value = value[prefix.len .. ^1]
    if src.deriveMc.kind != tkNone:
      value = applyTransform(value, src.deriveMc)
    result.add(value)

  result = dedupe(result)
  result.sortVersionsDesc()