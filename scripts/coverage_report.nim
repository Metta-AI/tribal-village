## coverage_report.nim - Automated code coverage reporter for test suite
##
## Static analysis tool that identifies which exported procs/funcs in src/*.nim
## are referenced by the test suite. Outputs a markdown coverage summary.
##
## Usage:
##   nim c -r scripts/coverage_report.nim
##
## Environment variables:
##   TV_COV_SRC_DIR    - Source directory to scan (default: src)
##   TV_COV_TEST_DIR   - Test directory to scan (default: tests)
##   TV_COV_OUTPUT     - Output file path (default: stdout)
##   TV_COV_SHOW_ALL   - "1" to show all procs, not just untested (default: 0)

import std/[os, strutils, strformat, sets, algorithm, sequtils]

type
  ProcInfo = object
    name: string
    file: string
    line: int
    exported: bool

  ModuleCoverage = object
    file: string
    totalProcs: int
    testedProcs: int
    untestedNames: seq[string]

proc extractProcs(filePath: string): seq[ProcInfo] =
  ## Parse a Nim source file and extract proc/func definitions.
  let content = readFile(filePath)
  let lines = content.splitLines()
  let relPath = filePath.extractFilename()

  for i, line in lines:
    let stripped = line.strip()
    # Match proc/func definitions at the start of a line (not indented continuations)
    if line.len > 0 and line[0] notin {' ', '\t', '#'}:
      for keyword in ["proc ", "func "]:
        if stripped.startsWith(keyword):
          let rest = stripped[keyword.len .. ^1]
          # Extract the proc name (up to first non-ident char)
          var name = ""
          for ch in rest:
            if ch in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
              name.add(ch)
            else:
              break
          if name.len > 0:
            let exported = rest.len > name.len and rest[name.len] == '*'
            result.add(ProcInfo(
              name: name,
              file: relPath,
              line: i + 1,
              exported: exported
            ))

proc scanTestReferences(testDir: string): HashSet[string] =
  ## Scan all test files and collect identifiers referenced.
  for entry in walkDir(testDir):
    if entry.kind == pcFile and entry.path.endsWith(".nim"):
      let content = readFile(entry.path)
      # Collect all word tokens from test files
      var i = 0
      while i < content.len:
        if content[i] in {'a'..'z', 'A'..'Z', '_'}:
          var word = ""
          while i < content.len and content[i] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
            word.add(content[i])
            inc i
          result.incl(word)
        elif content[i] == '#':
          # Skip comments to end of line
          while i < content.len and content[i] != '\n':
            inc i
        else:
          inc i

proc computeCoverage(srcDir, testDir: string): seq[ModuleCoverage] =
  ## Compute per-module coverage by checking which exported procs appear in tests.
  let testRefs = scanTestReferences(testDir)

  for entry in walkDir(srcDir):
    if entry.kind == pcFile and entry.path.endsWith(".nim"):
      let procs = extractProcs(entry.path)
      let exported = procs.filterIt(it.exported)
      if exported.len == 0:
        continue

      var tested = 0
      var untested: seq[string]
      for p in exported:
        if p.name in testRefs:
          inc tested
        else:
          untested.add(p.name)

      result.add(ModuleCoverage(
        file: entry.path.extractFilename(),
        totalProcs: exported.len,
        testedProcs: tested,
        untestedNames: untested
      ))

  # Also scan scripted/ subdirectory if present
  let scriptedDir = srcDir / "scripted"
  if dirExists(scriptedDir):
    for entry in walkDir(scriptedDir):
      if entry.kind == pcFile and entry.path.endsWith(".nim"):
        let procs = extractProcs(entry.path)
        let exported = procs.filterIt(it.exported)
        if exported.len == 0:
          continue

        var tested = 0
        var untested: seq[string]
        for p in exported:
          if p.name in testRefs:
            inc tested
          else:
            untested.add(p.name)

        result.add(ModuleCoverage(
          file: "scripted/" & entry.path.extractFilename(),
          totalProcs: exported.len,
          testedProcs: tested,
          untestedNames: untested
        ))

  result.sort(proc(a, b: ModuleCoverage): int =
    # Sort by coverage % ascending (least covered first)
    let aPct = if a.totalProcs > 0: a.testedProcs * 100 div a.totalProcs else: 100
    let bPct = if b.totalProcs > 0: b.testedProcs * 100 div b.totalProcs else: 100
    result = cmp(aPct, bPct)
    if result == 0:
      result = cmp(a.file, b.file)
  )

proc formatMarkdown(modules: seq[ModuleCoverage], showAll: bool): string =
  ## Generate markdown coverage report.
  var totalProcs = 0
  var totalTested = 0
  for m in modules:
    totalProcs += m.totalProcs
    totalTested += m.testedProcs

  let overallPct = if totalProcs > 0: totalTested * 100 div totalProcs else: 0

  result.add("# Test Coverage Report\n\n")
  result.add(&"**Overall:** {totalTested}/{totalProcs} exported procs referenced by tests ({overallPct}%)\n\n")

  # Summary table
  result.add("## Per-Module Coverage\n\n")
  result.add("| Module | Tested | Total | Coverage | Untested |\n")
  result.add("|--------|-------:|------:|---------:|----------|\n")

  for m in modules:
    let pct = if m.totalProcs > 0: m.testedProcs * 100 div m.totalProcs else: 100
    let untestedStr = if m.untestedNames.len > 0:
      m.untestedNames.join(", ")
    else:
      "-"

    if showAll or m.untestedNames.len > 0:
      result.add(&"| {m.file} | {m.testedProcs} | {m.totalProcs} | {pct}% | {untestedStr} |\n")

  # Fully covered modules summary
  let fullyCovered = modules.filterIt(it.untestedNames.len == 0)
  if fullyCovered.len > 0 and not showAll:
    result.add(&"\n*{fullyCovered.len} modules with 100% reference coverage omitted. Set TV_COV_SHOW_ALL=1 to include.*\n")

  # Untested procs list
  var allUntested: seq[tuple[file: string, name: string]]
  for m in modules:
    for name in m.untestedNames:
      allUntested.add((m.file, name))

  if allUntested.len > 0:
    result.add("\n## Untested Exported Procs\n\n")
    result.add(&"**{allUntested.len} exported procs** not referenced in any test file:\n\n")
    for item in allUntested:
      result.add(&"- `{item.file}`: `{item.name}`\n")

proc main() =
  let srcDir = getEnv("TV_COV_SRC_DIR", "src")
  let testDir = getEnv("TV_COV_TEST_DIR", "tests")
  let outputPath = getEnv("TV_COV_OUTPUT", "")
  let showAll = getEnv("TV_COV_SHOW_ALL", "0") == "1"

  if not dirExists(srcDir):
    echo &"Error: source directory '{srcDir}' not found"
    quit(1)
  if not dirExists(testDir):
    echo &"Error: test directory '{testDir}' not found"
    quit(1)

  let modules = computeCoverage(srcDir, testDir)
  let report = formatMarkdown(modules, showAll)

  if outputPath.len > 0:
    writeFile(outputPath, report)
    echo &"Coverage report written to {outputPath}"
  else:
    echo report

main()
