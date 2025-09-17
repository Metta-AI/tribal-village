proc consoleLog(msg: cstring) {.importc: "console.log".}
proc consoleError(msg: cstring) {.importc: "console.error".}

proc rawOutput(message: string) =
  consoleLog(message.cstring)

proc panic(message: string) =
  consoleError(("Nim panic: " & message).cstring)
  while true:
    discard
