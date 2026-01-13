# Agent Instructions

## Repo Sync (required)
At the start of each prompt, run:
`git pull`

## Validation Steps (required)
1. Ensure Nim code compiles:
   `nim c -d:release tribal_village.nim`
2. Ensure the main play command runs (15s timeout):
   `timeout 15s nim r -d:release tribal_village.nim`
   (On macOS without `timeout`, use `gtimeout` from coreutils.)
3. Run the test suite as the final step:
   `nim r --path:src tests/ai_harness.nim`

## Post-Validation Steps (required)
After the 15s play run and AI harness tests pass:
1. Commit your changes.
2. Fetch to ensure you're up to date.
3. Merge `main` (or rebase) and resolve conflicts sensibly.
4. Push to the remote.
