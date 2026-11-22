import std/[os, osproc, strutils]
import cliprompts
import ./[model, util]

type
  InstallVars* = object
    mc*: string
    loader*: string
    installer*: string
    dir*: string
    loaderId*: string
    loaderName*: string
    file*: string ## file produced by the last download step

proc varPairs*(vars: InstallVars): seq[(string, string)] =
  @[
    ("mc", vars.mc),
    ("loader", vars.loader),
    ("installer", vars.installer),
    ("dir", vars.dir),
    ("loaderId", vars.loaderId),
    ("loaderName", vars.loaderName),
    ("file", vars.file)
  ]

proc expandVars*(text: string, vars: InstallVars): string =
  expand(text, vars.varPairs())

proc tailLines(text: string, count = 12): string =
  let lines = text.strip().splitLines()
  let start = max(0, lines.len - count)
  if lines.len == 0:
    return ""
  lines[start .. ^1].join("\n")

proc runStep(step: ScenarioStep, vars: var InstallVars) =
  case step.kind
  of stDownload:
    let url = expandVars(step.url, vars)
    if url.len == 0:
      fail("download step has no url")
    var file = expandVars(step.file, vars)
    if file.len == 0:
      file = fileBaseName(url)
    let parent = parentDir(file)
    if parent.len > 0 and not dirExists(parent):
      createDir(parent)
    info("Downloading " & file)
    downloadTo(url, file)
    vars.file = file
    success("Saved " & file)

  of stRun:
    let command = expandVars(step.command, vars)
    if command.len == 0:
      fail("run step has no command")
    info("Running: " & command)
    let (output, code) = execCmdEx(command)
    if code != 0:
      let details = tailLines(output)
      if step.optional:
        hint("Command failed with exit code " & $code & ", continuing: " & details)
      else:
        fail("command failed with exit code " & $code &
          (if details.len > 0: "\n" & details else: ""))
    else:
      success("Command finished")

  of stWrite:
    let file = expandVars(step.file, vars)
    if file.len == 0:
      fail("write step has no file")
    if fileExists(file) and not step.overwrite:
      hint("Keeping existing " & file)
      return
    let parent = parentDir(file)
    if parent.len > 0 and not dirExists(parent):
      createDir(parent)
    writeFile(file, expandVars(step.content, vars))
    success("Wrote " & file)

  of stReplace:
    let file = expandVars(step.file, vars)
    if file.len == 0:
      fail("replace step has no file")
    if not fileExists(file):
      if step.onlyIfExists:
        hint("No " & file & " to update")
        return
      fail("cannot update missing file " & file)
    let content = readFile(file)
    let needle = expandVars(step.find, vars)
    if needle.len == 0:
      fail("replace step has no 'find' value")
    writeFile(file, content.replace(needle, expandVars(step.replace, vars)))
    success("Updated " & file)

  of stMkdir:
    let dir = expandVars(step.file, vars)
    if dir.len == 0:
      fail("mkdir step has no file (directory) value")
    createDir(dir)
    success("Created " & dir)

  of stRequire:
    let file = expandVars(step.file, vars)
    if file.len > 0 and not fileExists(file):
      if step.optional:
        hint("Missing optional " & file)
      else:
        fail("expected " & file & " to be created, but it is missing")
    else:
      success("Verified " & file)

  of stCopy:
    let source = expandVars(step.source, vars)
    let target = expandVars(step.target, vars)
    if source.len == 0 or target.len == 0:
      fail("copy step needs 'source' and 'target'")
    if not fileExists(source):
      if step.optional:
        hint("Missing optional source " & source)
        return
      fail("cannot copy missing file " & source)
    let parent = parentDir(target)
    if parent.len > 0 and not dirExists(parent):
      createDir(parent)
    copyFile(source, target)
    success("Copied " & source & " -> " & target)

proc runScenario*(loader: LoaderDef, vars: var InstallVars) =
  ## Executes the loader's declarative scenario inside the current directory.
  for step in loader.scenario:
    runStep(step, vars)