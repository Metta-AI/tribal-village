# Compatibility entrypoint.
#
# Some tooling and harnesses expect the main module at `src/tribal_village.nim`,
# but the canonical entrypoint lives at the repo root (`tribal_village.nim`).
include "../tribal_village.nim"

