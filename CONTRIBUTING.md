# Contributing to Tribal Village

This guide covers the conventions, processes, and expectations for contributing to Tribal Village.

## Code Style

Tribal Village is written primarily in **Nim** with a Python wrapper layer. Follow these conventions:

### Nim Conventions

- **Indentation**: 2 spaces, no tabs.
- **Functions**: `lowerCamelCase` (e.g., `decideAction`, `calculateFlowRate`).
- **Types and Enums**: `PascalCase` (e.g., `AgentUnitClass`, `UnitVillager`).
- **Constants**: `PascalCase` (e.g., `ResourceNodeInitial`, `MapRoomObjectsTeams`).
- **Visibility**: Use trailing `*` for public exports (e.g., `proc doThing*()`, `field*: int`). Omit for private.
- **Doc comments**: Use `##`. Use `#` for inline notes.
- **Pragmas**: Use `{.inline.}` for hot-path functions. Group with `{.push inline.}` / `{.pop.}`.
- **Memory management**: The project uses `--mm:arc`.
- **Imports**: Use `std/` prefix for stdlib imports (e.g., `import std/tables`).
- **Type hub**: Shared types live in `src/types.nim` to break circular dependencies.

### Python Conventions

- Python 3.12+.
- Standard PEP 8. The CLI uses `typer` and `rich`.

## Branch Naming

Branches follow the pattern:

```
polecat/<agent-name>/tv-<ticket-id>@<hash>
```

For example: `polecat/coma/tv-qfd0j@mkyk5b8l`.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) with the ticket ID:

```
feat: Add unit upgrades and promotion chains (tv-n6wec)
fix: Wonder countdown starts on completion, not placement (tv-1m0s2)
perf: Optimize AI tick with grid-local scans (tv-a5gd5)
chore: Gitignore build artifact src/ffi
```

**Prefixes:**
- `feat:` - New feature or capability
- `fix:` - Bug fix
- `perf:` - Performance improvement
- `chore:` - Maintenance, config, CI
- `docs:` - Documentation only
- `refactor:` - Code restructure without behavior change
- `test:` - Test additions or fixes

Always include the ticket ID in parentheses at the end when one is assigned (e.g., `(tv-abc12)`).

## Testing Requirements

All changes to Nim source code must pass the full validation sequence before merge.

### Validation Steps

1. **Compile check** -- confirms the code builds:
   ```bash
   nim c -d:release tribal_village.nim
   ```

2. **Smoke test** -- confirms the game runs without crashing (15-second timeout):
   ```bash
   timeout 15s nim r -d:release tribal_village.nim
   ```
   On macOS without `timeout`, use `gtimeout` from coreutils.

3. **Test suite** -- runs all domain tests via the AI harness:
   ```bash
   nim r --path:src tests/ai_harness.nim
   ```

4. **Full test suite** (optional but recommended):
   ```bash
   nim r --path:src scripts/run_all_tests.nim
   ```

### Writing Tests

Tests live in `tests/` and use Nim's built-in `unittest` module. Domain tests are organized by feature area (e.g., `domain_economy.nim`, `domain_combat_melee.nim`).

Test utilities in `tests/test_utils.nim` provide helpers:

```nim
import std/unittest
import environment, types, test_utils

suite "Feature Name":
  test "specific behavior":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    # ... setup and assertions
    check condition == expected
```

Key helpers: `makeEmptyEnv()`, `addAgentAt()`, `addBuilding()`, `addResource()`, `setStockpile()`, `stepAction()`, `stepNoop()`.

## PR Process and Review

### Workflow

1. **Sync** -- pull latest `main` before starting work:
   ```bash
   git pull
   ```

2. **Implement** -- make your changes on a feature branch.

3. **Validate** -- run all three validation steps (compile, smoke test, test suite).

4. **Commit** -- use conventional commit messages with ticket IDs.

5. **Merge main** -- rebase or merge `main` and resolve any conflicts:
   ```bash
   git pull --rebase
   ```

6. **Push** -- push your branch to the remote:
   ```bash
   git push
   ```

### Review Expectations

- Changes must compile and pass the test suite.
- New features should include tests covering the core behavior.
- Performance-sensitive changes should include profiling data or benchmarks.
- Keep PRs focused -- one logical change per PR.

## How to Run Validation

Quick reference for the full validation cycle:

```bash
# 1. Compile
nim c -d:release tribal_village.nim

# 2. Smoke test
timeout 15s nim r -d:release tribal_village.nim

# 3. AI harness tests
nim r --path:src tests/ai_harness.nim

# 4. (Optional) Full test suite
nim r --path:src scripts/run_all_tests.nim
```

See `docs/quickstart.md` for build prerequisites, environment variables, and troubleshooting.

## Filing Issues

This project uses **Beads** (`bd`) for task and issue tracking.

```bash
# List current issues
bd list

# Show issue details
bd show tv-<id>

# Create a new issue
bd create --type bug --priority P1 --title "Description of the problem"

# Update issue status
bd update tv-<id> --status=in_progress
bd update tv-<id> --status=done

# Sync task state
bd sync
```

When filing a bug, include:
- Steps to reproduce
- Expected vs. actual behavior
- Relevant log output or test failures
- The ticket ID of any related work

## Project Structure

```
tribal_village/
  src/              # Nim source (environment, AI, rendering, combat, etc.)
  tests/            # Nim tests (domain_*.nim files + harnesses)
  tribal_village_env/  # Python wrapper and CLI
  docs/             # Design and reference documentation
  data/             # Sprites, fonts, UI assets
  scripts/          # Build, profiling, and generation scripts
```

See `docs/README.md` for the full documentation index.
