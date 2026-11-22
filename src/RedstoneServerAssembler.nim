import std/[os, tables]
import cliprompts
import rsa/[meta, util, model, loaderstore, versionfetch, flow, cli]

var terminalUsed = false

proc printHeader() =
  info(ProgramName & " v" & Version)
  continuing(Description)
  continuing("By using the program, you are indicating your agreement to Minecraft EULA (" & EulaUrl & ")")
  continuing("by " & Author)

proc printLoaders(registry: LoaderRegistry) =
  for id in registry.ids:
    let loader = registry.defs[id]
    echo id & "\t" & loader.name & "\t" & loader.description

proc printVersions(registry: LoaderRegistry, opts: CliOptions) =
  if opts.loader.len == 0:
    fail("--loader is required with --list-versions")
  let loader = registry.getLoader(opts.loader)
  if opts.mcVersion.len == 0:
    for version in fetchVersions(loader.gameVersions):
      echo version
  else:
    for version in fetchVersions(loader.loaderVersions, opts.mcVersion):
      echo version

proc main() =
  let opts = parseCli(commandLineParams())

  if opts.showHelp:
    stdout.write(usage())
    return
  if opts.showVersion:
    echo Version
    return

  let registry = loadRegistry()
  if opts.listLoaders:
    printLoaders(registry)
    return
  if opts.listVersions:
    printVersions(registry, opts)
    return

  printHeader()

  var doPreconfig = opts.doPreconfig
  var cfg = opts.config
  var selection: Selection

  if opts.nonInteractive:
    selection = selectionFromCli(registry, opts)
  else:
    terminalUsed = true
    selection = chooseInteractive(registry)
    doPreconfig = promptBool("Pre-configure the server?", default = doPreconfig)
    if doPreconfig:
      cfg = promptPreconfig(cfg)

  install(selection, opts.targetDir, doPreconfig, cfg)

when isMainModule:
  try:
    main()
  except RsaError as e:
    error(e.msg)
    quit(1)
  except CatchableError as e:
    error("unexpected error: " & e.msg)
    quit(1)
  finally:
    if terminalUsed:
      restoreTerminalState()