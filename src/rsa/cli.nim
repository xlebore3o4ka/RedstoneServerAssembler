import std/strutils
import ./[model, meta, util]

proc usage*(): string =
  """
RedstoneServerAssembler v""" & Version & """

""" & Description & """

Usage:
  RedstoneServerAssembler [options]

Modes:
  (no mode)                Interactive dialogue.
  -n, --non-interactive    No prompts, only flags. Requires --loader and --mc-version.

General:
  -h, --help               Show this help.
  -v, --version            Show the program version.
      --list-loaders       List available loaders and exit.
      --list-versions      List versions for --loader (and --mc-version) and exit.
      --loader <id>        Loader id, e.g. fabric, neoforge, forge.
      --mc-version <ver>   Minecraft version.
      --loader-version <ver>     Loader version (default: latest stable).
      --installer-version <ver>  Installer version (default: latest stable).
      --dir <path>         Target directory (default: current directory).
      --no-preconfig       Do not write server.properties.

Server properties:
      --port <n>                 server-port
      --ip <addr>                server-ip
      --max-players <n>          max-players
      --motd <text>              motd
      --online-mode [true|false] online-mode
      --whitelist [true|false]   white-list
      --gamemode <mode>          survival, creative, adventure, spectator
      --difficulty <level>       peaceful, easy, normal, hard
      --level-name <name>        level-name
      --view-distance <n>        view-distance
      --simulation-distance <n>  simulation-distance
      --spawn-protection <n>     spawn-protection
      --op-permission-level <n>  op-permission-level
      --generate-structures [true|false]  generate-structures
      --level-type <type>        level-type
      --allow-flight [true|false]         allow-flight

Flags that take a value also accept the --flag=value form. Boolean flags accept
--flag, --flag false and --no-flag.

Examples:
  RedstoneServerAssembler
  RedstoneServerAssembler -n --loader neoforge --mc-version 1.21.1 --dir srv
  RedstoneServerAssembler -n --loader forge --mc-version 1.21.1 --port 25570 --online-mode true
  RedstoneServerAssembler --list-versions --loader fabric --mc-version 1.21.1
"""

const
  ValueOptions = [
    "loader", "mc-version", "loader-version", "installer-version", "dir",
    "port", "server-port", "ip", "server-ip", "max-players", "motd",
    "gamemode", "difficulty", "level-name", "view-distance",
    "simulation-distance", "spawn-protection", "op-permission-level",
    "level-type"
  ]
  BoolOptions = [
    "preconfig", "online-mode", "whitelist", "white-list",
    "generate-structures", "allow-flight"
  ]
  SwitchOptions = [
    "h", "help", "v", "version", "list-loaders", "list-versions",
    "n", "non-interactive", "no-input"
  ]

proc parseBoolFlag(value, flag: string): bool =
  case value.toLowerAscii()
  of "true", "1", "yes", "on", "y": result = true
  of "false", "0", "no", "off", "n": result = false
  else: fail("invalid value for --" & flag & ": " & value)

proc isBoolLiteral(value: string): bool =
  case value.toLowerAscii()
  of "true", "1", "yes", "on", "y", "false", "0", "no", "off", "n": true
  else: false

proc parseIntFlag(value, flag: string): int =
  try:
    result = parseInt(value)
  except ValueError:
    fail("invalid number for --" & flag & ": " & value)

proc parseGamemode(value: string): Gamemode =
  case value.toLowerAscii()
  of "survival": gmSurvival
  of "creative": gmCreative
  of "adventure": gmAdventure
  of "spectator": gmSpectator
  else: fail("invalid gamemode: " & value & " (expected survival, creative, adventure or spectator)")

proc parseDifficulty(value: string): Difficulty =
  case value.toLowerAscii()
  of "peaceful": dfPeaceful
  of "easy": dfEasy
  of "normal": dfNormal
  of "hard": dfHard
  else: fail("invalid difficulty: " & value & " (expected peaceful, easy, normal or hard)")

proc boolValue(value: string, flag: string, negated: bool): bool =
  if value.len > 0:
    if negated:
      fail("--no-" & flag & " does not take a value")
    parseBoolFlag(value, flag)
  else:
    not negated

proc parseCli*(args: seq[string]): CliOptions =
  result = defaultCliOptions()
  var i = 0
  while i < args.len:
    let arg = args[i]
    if not arg.startsWith("-") or arg == "-":
      fail("unexpected argument: " & arg)

    var name: string
    var value = ""
    var explicit = false

    if arg.startsWith("--"):
      let body = arg[2 .. ^1]
      if body.len == 0:
        fail("unexpected argument: --")
      let separator = body.find({'=', ':'})
      if separator >= 0:
        name = body[0 ..< separator]
        value = body[separator + 1 .. ^1]
        explicit = true
      else:
        name = body
    else:
      name = arg[1 .. ^1]

    if name in SwitchOptions:
      if explicit:
        fail("--" & name & " does not take a value")
      case name
      of "h", "help":
        result.showHelp = true
      of "v", "version":
        result.showVersion = true
      of "list-loaders":
        result.listLoaders = true
      of "list-versions":
        result.listVersions = true
      of "n", "non-interactive", "no-input":
        result.nonInteractive = true
      else:
        discard
      inc i
      continue

    var negated = false
    if name.startsWith("no-"):
      let positive = name[3 .. ^1]
      if positive in BoolOptions and not explicit:
        negated = true
        name = positive

    if name in BoolOptions:
      if not explicit and i + 1 < args.len and isBoolLiteral(args[i + 1]):
        inc i
        value = args[i]
        explicit = true
      case name
      of "preconfig":
        result.doPreconfig = boolValue(value, name, negated)
      of "online-mode":
        result.config.onlineMode = boolValue(value, name, negated)
      of "whitelist", "white-list":
        result.config.whiteList = boolValue(value, name, negated)
      of "generate-structures":
        result.config.generateStructures = boolValue(value, name, negated)
      of "allow-flight":
        result.config.allowFlight = boolValue(value, name, negated)
      else:
        discard
      inc i
      continue

    if name in ValueOptions:
      if not explicit:
        if i + 1 >= args.len or args[i + 1].startsWith("--"):
          fail("--" & name & " requires a value")
        inc i
        value = args[i]
        explicit = true

      case name
      of "loader":
        result.loader = value
      of "mc-version":
        result.mcVersion = value
      of "loader-version":
        result.loaderVersion = value
      of "installer-version":
        result.installerVersion = value
      of "dir":
        result.targetDir = value
      of "port", "server-port":
        result.config.serverPort = parseIntFlag(value, name)
      of "ip", "server-ip":
        result.config.serverIp = value
      of "max-players":
        result.config.maxPlayers = parseIntFlag(value, name)
      of "motd":
        result.config.motd = value
      of "gamemode":
        result.config.gamemode = parseGamemode(value)
      of "difficulty":
        result.config.difficulty = parseDifficulty(value)
      of "level-name":
        result.config.levelName = value
      of "view-distance":
        result.config.viewDistance = parseIntFlag(value, name)
      of "simulation-distance":
        result.config.simulationDistance = parseIntFlag(value, name)
      of "spawn-protection":
        result.config.spawnProtection = parseIntFlag(value, name)
      of "op-permission-level":
        result.config.opPermissionLevel = parseIntFlag(value, name)
      of "level-type":
        result.config.levelType = value
      else:
        discard
      inc i
      continue

    fail("unknown option: " & arg)