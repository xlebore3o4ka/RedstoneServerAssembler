import std/[json, strutils]
import ./util

type
  VersionSourceKind* = enum
    vsJson          ## generic JSON array of objects
    vsMavenJson     ## maven API returning {"versions": [...]}
    vsMavenXml      ## maven-metadata.xml with <version> entries
    vsMojang        ## Mojang version manifest

  VersionSource* = object
    kind*: VersionSourceKind
    url*: string             ## may contain {mc}
    arrayPath*: string       ## dot path to the array of items
    versionPath*: string     ## dot path to the version string inside an item
    stablePath*: string      ## dot path to a stability flag
    stableValue*: string     ## value that marks a version as stable
    releaseTypes*: seq[string] ## Mojang manifest types to keep
    prefixTemplate*: string  ## prefix template (`{mc}-`) filtering one MC version
    prefixFromMc*: Transform ## computed prefix filtering one MC version
    stripPrefix*: bool       ## strip `prefixFromMc` from the returned version
    excludePattern*: string  ## regex; matching versions are dropped
    deriveMc*: Transform     ## turn a loader version into a Minecraft version

  StepKind* = enum
    stDownload
    stRun
    stWrite
    stReplace
    stMkdir
    stRequire
    stCopy

  ScenarioStep* = object
    kind*: StepKind
    url*: string
    file*: string
    command*: string
    content*: string
    find*: string
    replace*: string
    source*: string
    target*: string
    overwrite*: bool
    onlyIfExists*: bool
    optional*: bool

  LoaderDef* = object
    id*: string
    name*: string
    description*: string
    website*: string
    javaVersion*: string
    gameVersions*: VersionSource
    loaderVersions*: VersionSource
    installerVersions*: VersionSource
    hasInstallerVersions*: bool
    scenario*: seq[ScenarioStep]
    launch*: string ## command used to start the server after installation

  Gamemode* = enum
    gmSurvival = "survival"
    gmCreative = "creative"
    gmAdventure = "adventure"
    gmSpectator = "spectator"

  Difficulty* = enum
    dfPeaceful = "peaceful"
    dfEasy = "easy"
    dfNormal = "normal"
    dfHard = "hard"

  ServerConfig* = object
    serverPort*: int
    serverIp*: string
    maxPlayers*: int
    motd*: string
    onlineMode*: bool
    whiteList*: bool
    gamemode*: Gamemode
    difficulty*: Difficulty
    levelName*: string
    simulationDistance*: int
    viewDistance*: int
    spawnProtection*: int
    opPermissionLevel*: int
    generateStructures*: bool
    levelType*: string
    allowFlight*: bool

  CliOptions* = object
    showHelp*: bool
    showVersion*: bool
    listLoaders*: bool
    listVersions*: bool
    nonInteractive*: bool
    doPreconfig*: bool
    loader*: string
    mcVersion*: string
    loaderVersion*: string
    installerVersion*: string
    targetDir*: string
    config*: ServerConfig

proc defaultServerConfig*(): ServerConfig =
  ServerConfig(
    serverPort: 25565,
    serverIp: "",
    maxPlayers: 20,
    motd: "A RedstoneServerAssembled Minecraft Server",
    onlineMode: false,
    whiteList: false,
    gamemode: gmSurvival,
    difficulty: dfNormal,
    levelName: "world",
    simulationDistance: 10,
    viewDistance: 10,
    spawnProtection: 16,
    opPermissionLevel: 4,
    generateStructures: true,
    levelType: "",
    allowFlight: false
  )

proc defaultCliOptions*(): CliOptions =
  CliOptions(
    doPreconfig: true,
    targetDir: ".",
    config: defaultServerConfig()
  )

proc parseVersionSource*(node: JsonNode): VersionSource =
  if node.isNil or node.kind != JObject:
    fail("version source must be a JSON object")
  let kind = node.strOf("kind", "json").toLowerAscii()
  case kind
  of "json":
    result.kind = vsJson
  of "maven", "maven-json":
    result.kind = vsMavenJson
  of "maven-xml":
    result.kind = vsMavenXml
  of "mojang", "mojang-manifest":
    result.kind = vsMojang
  else:
    fail("unknown version source kind: " & kind)

  result.url = node.strOf("url")
  result.arrayPath = node.strOf("arrayPath", "")
  result.versionPath = node.strOf("versionPath", "version")
  result.stablePath = node.strOf("stablePath", "")
  result.stableValue = node.strOf("stableValue", "true")
  result.prefixTemplate = node.strOf("prefix", "")
  result.stripPrefix = node.boolOf("stripPrefix", false)
  result.excludePattern = node.strOf("exclude", "")
  if node.hasKey("releaseTypes"):
    for item in node["releaseTypes"]:
      result.releaseTypes.add(item.getStr())
  if result.releaseTypes.len == 0:
    result.releaseTypes = @["release"]
  if node.hasKey("prefixFromMc"):
    result.prefixFromMc = parseTransform(node["prefixFromMc"])
  if node.hasKey("deriveMc"):
    result.deriveMc = parseTransform(node["deriveMc"])

proc parseStep*(node: JsonNode): ScenarioStep =
  if node.kind != JObject:
    fail("scenario step must be a JSON object")
  let kind = node.strOf("type").toLowerAscii()
  case kind
  of "download":
    result.kind = stDownload
  of "run", "command":
    result.kind = stRun
  of "write", "write-file":
    result.kind = stWrite
  of "replace", "replace-file":
    result.kind = stReplace
  of "mkdir":
    result.kind = stMkdir
  of "require", "require-file":
    result.kind = stRequire
  of "copy":
    result.kind = stCopy
  else:
    fail("unknown scenario step type: " & kind)

  result.url = node.strOf("url")
  result.file = node.strOf("file")
  result.command = node.strOf("command")
  result.content = node.strOf("content")
  result.find = node.strOf("find")
  result.replace = node.strOf("replace")
  result.source = node.strOf("source")
  result.target = node.strOf("target")
  result.overwrite = node.boolOf("overwrite", true)
  result.onlyIfExists = node.boolOf("onlyIfExists", true)
  result.optional = node.boolOf("optional", false)

proc validate*(loader: LoaderDef) =
  if loader.id.len == 0:
    fail("loader definition has no id")
  if loader.name.len == 0:
    fail("loader '" & loader.id & "' has no name")
  if loader.gameVersions.url.len == 0:
    fail("loader '" & loader.id & "' has no gameVersions.url")
  if loader.loaderVersions.url.len == 0:
    fail("loader '" & loader.id & "' has no loaderVersions.url")
  if loader.scenario.len == 0:
    fail("loader '" & loader.id & "' has an empty scenario")

proc parseLoader*(node: JsonNode): LoaderDef =
  if node.kind != JObject:
    fail("loader definition must be a JSON object")
  result.id = node.strOf("id")
  result.name = node.strOf("name")
  result.description = node.strOf("description")
  result.website = node.strOf("website")
  result.javaVersion = node.strOf("javaVersion", "17")
  result.launch = node.strOf("launch")
  result.gameVersions = parseVersionSource(jsonPath(node, "gameVersions"))
  result.loaderVersions = parseVersionSource(jsonPath(node, "loaderVersions"))
  if node.hasKey("installerVersions"):
    result.installerVersions = parseVersionSource(node["installerVersions"])
    result.hasInstallerVersions = true
  if node.hasKey("scenario"):
    for item in node["scenario"]:
      result.scenario.add(parseStep(item))
  result.validate()