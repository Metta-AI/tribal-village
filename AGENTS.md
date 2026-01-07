# Agent Instructions

## Validation Steps (required)
1. Ensure Nim code compiles:
   `nim c -d:release tribal_village.nim`
2. Ensure the main play command runs (15s timeout):
   `timeout 15s nim r -d:release tribal_village.nim`
   (On macOS without `timeout`, use `gtimeout` from coreutils.)
3. Run the test suite as the final step:
   `nim r --path:src tests/ai_harness.nim`
