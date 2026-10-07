import cliprompts
import std/[os, osproc, parsecfg, streams, httpclient, json, sequtils, strformat, tables, strutils]

type
  CoreEnum = enum
    ceFabric = "Fabric"

  CoreConfig = tuple
    gameVersionsUrl: string
    installerVersionsUrl: string
    loaderVersionsUrlTemplate: string
    endpointTemplate: string
    filenameTemplate: string

const coreConfigs: Table[CoreEnum, CoreConfig] = {
  ceFabric: (
    gameVersionsUrl:           "https://meta.fabricmc.net/v2/versions/game",
    installerVersionsUrl:      "https://meta.fabricmc.net/v2/versions/installer",
    loaderVersionsUrlTemplate: "https://meta.fabricmc.net/v2/versions/loader/{game}",
    endpointTemplate:          "https://meta.fabricmc.net/v2/versions/loader/{game}/{loader}/{installer}/server/jar",
    filenameTemplate:          "fabric-server-mc-{game}-loader-{installer}.jar"
  )
}.toTable

proc fetchFabricVersions*(url: string, versionsName: string, stableOnly: bool = true): seq[string] =
  info(&"Downloading {versionsName} versions...")
  let client = newHttpClient()
  try:
    let response = client.getContent(url)
    let json = parseJson(response)
    let elems = json.getElems()
    
    result = if stableOnly:
      elems.filterIt(it["stable"].getBool()).mapIt(it["version"].getStr())
    else:
      elems.mapIt(it["version"].getStr())
    
    success(&"Loading of {versionsName} versions is completed")
  except Exception as e:
    error(&"Failed to fetch {versionsName} versions: {e.msg}")
    quit(1)
  finally:
    client.close()

proc fetchFabricLoaderVersions(game: string, stableOnly: bool = true): seq[string] =
  info(&"Downloading loader versions...")
  let client = newHttpClient()
  try:
    let response = client.getContent(coreConfigs[ceFabric].loaderVersionsUrlTemplate.replace("{game}", game))
    let json = parseJson(response)
    let elems = json.getElems()
    
    result = if stableOnly:
      elems.mapIt(it["loader"]).filterIt(it["stable"].getBool()).mapIt(it["version"].getStr())
    else:
      elems.mapIt(it["loader"]).mapIt(it["version"].getStr())
    
    success(&"Loading of loader versions is completed")
  except Exception as e:
    error(&"Failed to fetch loader versions: {e.msg}")
    quit(1)
  finally:
    client.close()

proc downloadFabricLoader*(gameVersion: string, loaderVersion: string, installerVersion: string): string =
  const config = coreConfigs[ceFabric]
  let client = newHttpClient()
  try:
    let url = config.endpointTemplate
      .replace("{game}", gameVersion)
      .replace("{loader}", loaderVersion)
      .replace("{installer}", installerVersion)
    
    info(&"Downloading loader from: {url}")
    let response = client.getContent(url)
    
    let fileName = config.filenameTemplate
      .replace("{game}", gameVersion)
      .replace("{loader}", loaderVersion)
      .replace("{installer}", installerVersion)
    
    writeFile(fileName, response)
    success(&"Loader downloaded as: {fileName}")
    return fileName
  except Exception as e:
    error(&"Failed to download loader: {e.msg}")
    quit(1)
  finally:
    client.close()

proc setupServer(filename: string) =
  info(&"Downloading server from {filename}")
  let (_, exitcode) = execCmdEx(&"java -jar {filename}")
  if exitcode != 0:
    error(&"The server download completed with exit code: {exitcode}")
    quit(exitcode)
  success("The server download completed successfully")

let output = execProcess("nimble dump")
let config = output.newStringStream().loadConfig()

let ver     = config.getSectionValue("", "version")
let desc    = config.getSectionValue("", "desc")
let author  = config.getSectionValue("", "author")

# Assembly

info(&"Redstone Server Assembler v{ver}")
continuing(desc)
continuing("By using the program, you are indicating your agreement to minecraft EULA (https://aka.ms/MinecraftEULA)")
continuing(&"by {author}")

let core = promptEnum[CoreEnum]("Core:")
let coreConfig = coreConfigs[core]

# Fetching versions

var gameStable, installerStable, loaderStable: seq[string]

# Game version

case core:
of ceFabric:
  gameStable      = fetchFabricVersions(coreConfig.gameVersionsUrl, "minecraft")

let gameVersion = gameStable[promptSearch("Minecraft version:", gameStable)]

# Installer & loader versions

case core:
of ceFabric:
  installerStable = fetchFabricVersions(coreConfig.installerVersionsUrl, "installer")
  loaderStable = fetchFabricLoaderVersions(gameVersion)

var loaderVersion: string 
if installerStable.len > 1:
  loaderVersion = loaderStable[promptSearch("Loader version:", loaderStable)]
else:
  loaderVersion = loaderStable[0]
  prompt("Loader version:")
  answer(&"{loaderVersion} [only available]")

var installerVersion: string 
if installerStable.len > 1:
  installerVersion = installerStable[promptSearch("Installer version:", installerStable)]
else:
  installerVersion = installerStable[0]
  prompt("Installer version:")
  answer(&"{installerVersion} [only available]")

# Pre-congiguration

type
  GameModeKind   = enum
    gmkSurvival  = "survival"
    gmkCreative  = "creative"
    gmkAdventure = "adventure"

  DifficultyKind = enum
    dkPeaceful   = "peaceful"
    dkEasy       = "easy"
    dkNormal     = "normal"
    dkHard       = "hard"

  PreConfig   =         object
    serverPort:         int            = 25565
    serverIp:           string         # no default
    maxPlayers:         int            = 20
    motd:               string         = "A RedstoneServerAssembled Minecraft Server"
    onlineMode:         bool           = false
    whiteList:          bool           = false
    gamemode:           GameModeKind   = gmkSurvival
    difficulty:         DifficultyKind = dkNormal
    levelName:          string         = "world"
    simulationDistance: int            = 10
    viewDistance:       int            = 10
    spawnProtection:    Natural        = 16
    opPermissionLevel:  Natural        = 4
    generateStructures: bool           = true
    levelType:          string         # no default
    allowFlight:        bool           = false

let doPreconfig = promptBool("Pre-configure the server?", default = true)

var preConfig = PreConfig()

if doPreconfig:
  preConfig.serverPort         = promptInt(    "[server-port] Enter server port",                  default = preConfig.serverPort )         ; continuing("-")
  preConfig.serverIp           = promptString( "[server-ip] Enter IP address",                     default = "leave it as it is")           ; continuing("-")
  preConfig.maxPlayers         = promptInt(    "[max-players] Enter max players",                  default = preConfig.maxPlayers )         ; continuing("-")
  preConfig.motd               = promptString( "[motd] Enter MOTD",                                default = preConfig.motd )               ; continuing("-")
  preConfig.onlineMode         = promptBool(   "[online-mode] Enable online mode?",                default = preConfig.onlineMode )         ; continuing("-")
  preConfig.whiteList          = promptBool(   "[white-list] Enable whitelist?",                   default = preConfig.whiteList )          ; continuing("-")
  preConfig.gamemode           = promptEnum(   "[gamemode] Select gamemode",                       default = preConfig.gamemode )           ; continuing("-")
  preConfig.difficulty         = promptEnum(   "[difficulty] Select difficulty",                   default = preConfig.difficulty )         ; continuing("-")
  preConfig.levelName          = promptString( "[level-name] Enter level name",                    default = preConfig.levelName )          ; continuing("-")
  preConfig.viewDistance       = promptInt(    "[view-distance] Enter view distance",              default = preConfig.viewDistance )       ; continuing("-")
  preConfig.simulationDistance = promptInt(    "[simulation-distance] Enter simulation distance",  default = preConfig.simulationDistance ) ; continuing("-")
  preConfig.spawnProtection    = promptInt(    "[spawn-protection] Enter spawn protection radius", default = preConfig.spawnProtection )    ; continuing("-")
  preConfig.opPermissionLevel  = promptInt(    "[op-permission-level] Enter OP permission level",  default = preConfig.opPermissionLevel )  ; continuing("-")
  preConfig.generateStructures = promptBool(   "[generate-structures] Generate structures?",       default = preConfig.generateStructures ) ; continuing("-")
  preConfig.levelType          = promptString( "[level-type] Enter level type",                    default = "leave it as it is")           ; continuing("-")
  preConfig.allowFlight        = promptBool(   "[allow-flight] Allow flight?",                     default = preConfig.allowFlight )        ; continuing("-")


# Setup server

var downloadedFile: string
case core:
of ceFabric:
  downloadedFile = downloadFabricLoader(gameVersion, loaderVersion, installerVersion)

setupServer(downloadedFile)

if not fileExists("eula.txt"):
  error("The server was not loaded correctly (the eula.txt file is missing)")
  quit(1)

# By using the program, you are indicating your agreement to minecraft EULA (https://aka.ms/MinecraftEULA)
writeFile("eula.txt", readFile("eula.txt").replace("false", "true"))
hint("By using the program, you are indicating your agreement to minecraft EULA (https://aka.ms/MinecraftEULA)")
success("Agreement with the EULA")
