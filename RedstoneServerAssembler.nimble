# Package

version       = "0.2.0"
author        = "xlebore3o4ka"
description   = "The interactive CLI that automates Minecraft server setup — core, version, config, EULA, path, all in one dialog."
license       = "LGPL-3.0-only"
srcDir        = "src"
binDir        = "bin"
bin           = @["RedstoneServerAssembler"]


# Dependencies

requires "nim >= 2.2.10"
requires "cliprompts >= 0.1.2"

task myRun, "Running with the necessary compilation settings":
  exec "nim c -r -d:ssl -o:bin/" & bin[0] & " src/" & bin[0] & ".nim"