import std/[os, sequtils, strutils, tables]
import cliprompts
import ./[model, util, loaderstore, versionfetch, scenario, preconfig]

type
  Selection* = object
    loader*: LoaderDef
    mcVersion*: string
    loaderVersion*: string
    installerVersion*: string

proc latestVersion(src: VersionSource, mc = ""): string =
  let versions = fetchVersions(src, mc)
  if versions.len == 0:
    fail("no versions available")
  versions[0]

proc pickVersion(label: string, versions: seq[string]): string =
  if versions.len == 0:
    fail("no versions available for " & label.toLowerAscii())
  if versions.len == 1:
    prompt(label & ":")
    answer(versions[0] & " [only available]")
    return versions[0]
  versions[promptSearch(label & ":", versions)]

proc chooseInteractive*(registry: LoaderRegistry): Selection =
  let ids = registry.ids
  let names = ids.mapIt(registry.defs[it].name)
  var chosen = -1
  for index in promptSelection("Core:", names):
    chosen = int(index)
    break
  if chosen < 0:
    fail("no core selected")

  result.loader = registry.getLoader(ids[chosen])
  result.mcVersion = pickVersion("Minecraft version", fetchVersions(result.loader.gameVersions))
  result.loaderVersion = pickVersion("Loader version",
    fetchVersions(result.loader.loaderVersions, result.mcVersion))
  if result.loader.hasInstallerVersions:
    result.installerVersion = pickVersion("Installer version",
      fetchVersions(result.loader.installerVersions))
  else:
    result.installerVersion = result.loaderVersion

proc promptPreconfig*(current: ServerConfig): ServerConfig =
  result = current
  result.serverPort = promptInt("[server-port] Enter server port", default = current.serverPort)
  continuing("-")
  result.serverIp = promptString("[server-ip] Enter IP address", default = current.serverIp)
  continuing("-")
  result.maxPlayers = promptInt("[max-players] Enter max players", default = current.maxPlayers)
  continuing("-")
  result.motd = promptString("[motd] Enter MOTD", default = current.motd)
  continuing("-")
  result.onlineMode = promptBool("[online-mode] Enable online mode?", default = current.onlineMode)
  continuing("-")
  result.whiteList = promptBool("[white-list] Enable whitelist?", default = current.whiteList)
  continuing("-")
  result.gamemode = promptEnum("[gamemode] Select gamemode", default = current.gamemode)
  continuing("-")
  result.difficulty = promptEnum("[difficulty] Select difficulty", default = current.difficulty)
  continuing("-")
  result.levelName = promptString("[level-name] Enter level name", default = current.levelName)
  continuing("-")
  result.viewDistance = promptInt("[view-distance] Enter view distance", default = current.viewDistance)
  continuing("-")
  result.simulationDistance = promptInt("[simulation-distance] Enter simulation distance", default = current.simulationDistance)
  continuing("-")
  result.spawnProtection = promptInt("[spawn-protection] Enter spawn protection radius", default = current.spawnProtection)
  continuing("-")
  result.opPermissionLevel = promptInt("[op-permission-level] Enter OP permission level", default = current.opPermissionLevel)
  continuing("-")
  result.generateStructures = promptBool("[generate-structures] Generate structures?", default = current.generateStructures)
  continuing("-")
  result.levelType = promptString("[level-type] Enter level type", default = current.levelType)
  continuing("-")
  result.allowFlight = promptBool("[allow-flight] Allow flight?", default = current.allowFlight)

proc install*(selection: Selection, targetDir: string, doPreconfig: bool,
              cfg: ServerConfig) =
  var vars = InstallVars(
    mc: selection.mcVersion,
    loader: selection.loaderVersion,
    installer:
      if selection.installerVersion.len > 0: selection.installerVersion
      else: selection.loaderVersion,
    loaderId: selection.loader.id,
    loaderName: selection.loader.name
  )

  createDir(targetDir)
  vars.dir = absolutePath(targetDir)
  let previousDir = getCurrentDir()
  try:
    setCurrentDir(vars.dir)
    info("Assembling " & selection.loader.name & " " & selection.loaderVersion &
      " for Minecraft " & selection.mcVersion)
    runScenario(selection.loader, vars)
    writeEula(vars.dir)
    if doPreconfig:
      writeServerProperties(vars.dir, cfg)

    let launch = expandVars(selection.loader.launch, vars)
    discard writeStartScript(vars.dir, launch)
    success("Server is ready in " & vars.dir)
    if launch.len > 0:
      hint("Start it with: cd \"" & vars.dir & "\" && " & launch)
  finally:
    setCurrentDir(previousDir)

proc selectionFromCli*(registry: LoaderRegistry, opts: CliOptions): Selection =
  ## Builds a selection from flags without asking anything.
  if opts.loader.len == 0:
    fail("--loader is required with --non-interactive")
  if opts.mcVersion.len == 0:
    fail("--mc-version is required with --non-interactive")

  result.loader = registry.getLoader(opts.loader)
  result.mcVersion = opts.mcVersion
  result.loaderVersion =
    if opts.loaderVersion.len > 0: opts.loaderVersion
    else: latestVersion(result.loader.loaderVersions, result.mcVersion)
  if result.loader.hasInstallerVersions:
    result.installerVersion =
      if opts.installerVersion.len > 0: opts.installerVersion
      else: latestVersion(result.loader.installerVersions)
  else:
    result.installerVersion = result.loaderVersion
