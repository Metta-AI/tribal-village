## Tests for replay_common.nim - Shared replay serialization helpers.
##
## Tests round-trip serialization of change series (step, value) pairs
## and edge cases for parsing/serialization.
##
## Run: nim r --path:src tests/domain_replay_common.nim

import std/[unittest, json]
import replay_common

suite "Replay Common - serializeChanges":
  test "serializeChanges produces [[step, value], ...] format":
    let changes: ChangeSeries = @[
      (step: 0, value: newJInt(10)),
      (step: 5, value: newJInt(20)),
      (step: 10, value: newJInt(30))
    ]
    let result = serializeChanges(changes)
    check result.kind == JArray
    check result.len == 3
    check result[0][0].getInt() == 0
    check result[0][1].getInt() == 10
    check result[1][0].getInt() == 5
    check result[1][1].getInt() == 20
    check result[2][0].getInt() == 10
    check result[2][1].getInt() == 30

  test "serializeChanges empty list produces empty array":
    let changes: ChangeSeries = @[]
    let result = serializeChanges(changes)
    check result.kind == JArray
    check result.len == 0

  test "serializeChanges single entry":
    let changes: ChangeSeries = @[(step: 42, value: newJString("hello"))]
    let result = serializeChanges(changes)
    check result.len == 1
    check result[0][0].getInt() == 42
    check result[0][1].getStr() == "hello"

  test "serializeChanges preserves value types":
    let changes: ChangeSeries = @[
      (step: 0, value: newJBool(true)),
      (step: 1, value: newJFloat(3.14)),
      (step: 2, value: newJNull()),
      (step: 3, value: newJString("test"))
    ]
    let result = serializeChanges(changes)
    check result[0][1].kind == JBool
    check result[1][1].kind == JFloat
    check result[2][1].kind == JNull
    check result[3][1].kind == JString

suite "Replay Common - parseChanges":
  test "parseChanges round-trips with serializeChanges":
    let original: ChangeSeries = @[
      (step: 0, value: newJInt(100)),
      (step: 10, value: newJInt(200)),
      (step: 20, value: newJInt(300))
    ]
    let serialized = serializeChanges(original)
    let parsed = parseChanges(serialized)

    check parsed.len == original.len
    for i in 0 ..< parsed.len:
      check parsed[i].step == original[i].step
      check parsed[i].value == original[i].value

  test "parseChanges handles empty array":
    let empty = newJArray()
    let result = parseChanges(empty)
    check result.len == 0

  test "parseChanges handles nil input":
    let result = parseChanges(nil)
    check result.len == 0

  test "parseChanges handles non-array input":
    let obj = newJObject()
    let result = parseChanges(obj)
    check result.len == 0

  test "parseChanges skips malformed entries":
    var arr = newJArray()
    # Valid entry
    var valid = newJArray()
    valid.add(newJInt(5))
    valid.add(newJString("ok"))
    arr.add(valid)
    # Malformed: only one element
    var bad = newJArray()
    bad.add(newJInt(10))
    arr.add(bad)
    # Another valid entry
    var valid2 = newJArray()
    valid2.add(newJInt(15))
    valid2.add(newJInt(99))
    arr.add(valid2)

    let result = parseChanges(arr)
    check result.len == 2
    check result[0].step == 5
    check result[0].value.getStr() == "ok"
    check result[1].step == 15
    check result[1].value.getInt() == 99

  test "parseChanges handles non-array entries":
    var arr = newJArray()
    arr.add(newJInt(42))  # Not an array pair
    var valid = newJArray()
    valid.add(newJInt(0))
    valid.add(newJBool(true))
    arr.add(valid)

    let result = parseChanges(arr)
    check result.len == 1
    check result[0].step == 0
    check result[0].value.getBool() == true

suite "Replay Common - lastChangeValue":
  test "lastChangeValue returns last value":
    var series = newJArray()
    var entry1 = newJArray()
    entry1.add(newJInt(0))
    entry1.add(newJString("first"))
    series.add(entry1)
    var entry2 = newJArray()
    entry2.add(newJInt(5))
    entry2.add(newJString("second"))
    series.add(entry2)
    var entry3 = newJArray()
    entry3.add(newJInt(10))
    entry3.add(newJString("last"))
    series.add(entry3)

    let result = lastChangeValue(series)
    check result.getStr() == "last"

  test "lastChangeValue empty series returns null":
    let empty = newJArray()
    let result = lastChangeValue(empty)
    check result.kind == JNull

  test "lastChangeValue nil returns null":
    let result = lastChangeValue(nil)
    check result.kind == JNull

  test "lastChangeValue single entry":
    var series = newJArray()
    var entry = newJArray()
    entry.add(newJInt(0))
    entry.add(newJInt(42))
    series.add(entry)

    let result = lastChangeValue(series)
    check result.getInt() == 42

  test "lastChangeValue handles various value types":
    # Array value
    var series = newJArray()
    var entry = newJArray()
    entry.add(newJInt(0))
    var pos = newJArray()
    pos.add(newJInt(10))
    pos.add(newJInt(20))
    entry.add(pos)
    series.add(entry)

    let result = lastChangeValue(series)
    check result.kind == JArray
    check result[0].getInt() == 10
    check result[1].getInt() == 20

suite "Replay Common - Constants":
  test "ReplayVersion is positive":
    check ReplayVersion > 0
