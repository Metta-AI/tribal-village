# Orphaned Branch Audit Report (tv-wisp-f7vru)

Date: 2026-01-29

## Summary

- **Total remote branches (excl main):** 153
- **Fully merged to main (safe to delete):** 41
- **Unmerged branches:** 112
- **Unmerged in PR/refinery queue (being processed):** ~20
- **Truly orphaned (unmerged, not in any queue):** ~92

## Branches Safe to Delete (41 merged)

These branches are fully merged to main. Their commits are already in the main branch.
Deleting them loses no work.

| Branch | Notes |
|--------|-------|
| polecat/ace/tv-6by2b | merged |
| polecat/bullet/tv-wisp-2mu6 | merged |
| polecat/cheedo-mkuntnmu | merged (init branch) |
| polecat/cheedo/tv-luzl | merged |
| polecat/cheedo/tv-wisp-wmeqp | merged |
| polecat/citadel/tv-kmy2 | merged |
| polecat/corpus/tv-wisp-jnik | merged |
| polecat/dag/tv-i8zc | merged |
| polecat/dag/tv-wisp-9pond.1 | merged |
| polecat/dementus/tv-wisp-ayxun | merged |
| polecat/dinki/tv-wisp-oyub | merged |
| polecat/furiosa/tv-wisp-9pond.3 | merged |
| polecat/immortan/tv-wisp-c85p | merged |
| polecat/imperator/tv-wisp-t0m37 | merged |
| polecat/keeper/tv-wisp-9pond.5 | merged |
| polecat/morsov/tv-wisp-g9fzo | merged |
| polecat/nux/tv-5t68 | merged |
| polecat/nux/tv-jz6p8 | merged |
| polecat/prime/tv-wisp-wdia | merged |
| polecat/rictus/tv-4hel0 | merged |
| polecat/rictus/tv-wisp-jdbx9 | merged |
| polecat/rictus/tv-wisp-jnik | merged |
| polecat/scrotus/tv-wisp-gddu | merged |
| polecat/slit/tv-5evk (x2) | merged |
| polecat/slit/tv-96g | merged |
| polecat/slit/tv-af7q | merged |
| polecat/slit/tv-iied | merged |
| polecat/slit/tv-upwa | merged |
| polecat/splendid/tv-z20 | merged |
| polecat/toast/tv-19cx | merged |
| polecat/toast/tv-wisp-ptdv4 | merged |
| polecat/valkyrie/tv-03woh | merged |
| polecat/valkyrie/tv-b5hbh | merged |
| polecat/valkyrie/tv-jhet | merged |
| polecat/valkyrie/tv-mu59 | merged |
| polecat/valkyrie/tv-octv | merged |
| polecat/warboy/tv-xedzg | merged |
| polecat/wasteland/tv-l0oc | merged |
| pr/tv-aqx | merged |

## Branches in PR/Refinery Queue (being processed)

These have unmerged commits but are actively queued for merge:

| PR Branch | Content |
|-----------|---------|
| pr/tv-02pb | Pre-allocate pathfinding scratch space |
| pr/tv-2bk | EmergencyHeal behavior |
| pr/tv-3ns | Builder flee behavior |
| pr/tv-96g | True siege conversion |
| pr/tv-c035 | Spatial index for O(1) queries |
| pr/tv-ch8 | Class-specific combat overlay colors |
| pr/tv-v0lg | Incremental tint updates |
| pr/tv-wisp-8lgpq | Selection and command API |
| pr/tv-wisp-9pond.7 | Tech tree state queries FFI |
| pr/tv-wisp-g1xr | Reduce deep nesting in step.nim |

| Refinery Branch | Content |
|-----------------|---------|
| refinery/tv-wisp-alym | Market trading FFI (tv-wisp-9pond.6) |
| refinery/tv-wisp-bx6t | Tech tree queries FFI (tv-wisp-9pond.7) |
| refinery/tv-wisp-it6g | (empty - no commits ahead) |
| refinery/tv-wisp-mty1 | Observation layers docs (tv-wisp-9pond.4) |
| refinery/tv-wisp-vrw8 | Selection/command API (tv-wisp-8lgpq) |
| refinery/tv-wisp-x3g0 | wonderVictoryCountdown fix (tv-wisp-1rmd) |

## Orphaned Polecat Branches with Useful Unmerged Work

These branches have commits NOT in main and NOT in any PR/refinery queue. Grouped by issue.

### High-value features (new gameplay mechanics)

| Branch | Issue | Commit Summary |
|--------|-------|----------------|
| angharad/tv-6y4vc | tv-6y4vc | Regicide victory mode |
| angharad/tv-t74r7 | tv-t74r7 | Relic victory mode with monastery destruction |
| angharad/tv-vrjv9 | tv-vrjv9 | Control groups for unit selection |
| angharad/tv-vjdwq | tv-vjdwq | Replay analysis system for AI learning |
| splendid/tv-levht | tv-levht | King of the Hill victory mode |
| splendid/tv-n4zfb | tv-n4zfb | Rally points for production buildings |
| splendid/tv-wjuqo | tv-wjuqo | Unit garrisoning in buildings |
| valkyrie/tv-bus5q | tv-bus5q | Victory conditions system (conquest/wonder/relic) |
| warboy/tv-djq7t | tv-djq7t | Standard Victory Mode with toggles |
| splendid/tv-1m0s2 | tv-1m0s2 | Wonder countdown fix (starts on completion) |
| coma/tv-bovho | tv-bovho | Batch training UI with production queue |
| warboy/tv-9yzu1 | tv-9yzu1 | Per-unit training times and progress bar |
| warboy/tv-n6wec | tv-n6wec | Unit upgrades and promotion chains |
| organic/tv-14prc | tv-14prc | Trade Cog units for gold generation |
| coma/tv-morec | tv-morec | Castle unique technologies per civilization |
| nightrider/tv-wisp-wx7d | tv-wisp-wx7d | Monk conversion mechanic |
| blackfinger/tv-wisp-2jzw | tv-wisp-2jzw | University technologies |
| interceptor/tv-wisp-c9ep | tv-wisp-c9ep | Wonder victory condition |
| toecutter/tv-wisp-376f | tv-wisp-376f | Castle unique unit spawning |
| goose/tv-wisp-k0or | tv-wisp-k0or | Town Center garrison bonus |
| glory/tv-wisp-318k | tv-wisp-318k | Market trading mechanics |
| chumbucket/tv-wisp-746p | tv-wisp-746p | Attack-move command |
| slit/tv-wisp-746p | tv-wisp-746p | Attack-move command (duplicate) |
| nux/tv-wisp-gddu | tv-wisp-gddu | Idle villager detection and indicator |
| morsov/tv-p2vj5 | tv-p2vj5 | Wonder building |

### AI/behavior improvements

| Branch | Issue | Commit Summary |
|--------|-------|----------------|
| capable/tv-5v05h | tv-5v05h | Rush/boom/turtle strategy selection |
| dag/tv-13jvi | tv-13jvi | Scout behavior with enemy detection |
| dag/tv-6mlv | tv-6mlv | Inter-role coordination system |
| dementus/tv-d3qmf | tv-d3qmf | Adaptive difficulty for AI |
| rictus/tv-ilh | tv-ilh | Target swapping for fighters |
| rictus/tv-o3iyp | tv-o3iyp | Multi-unit coordination and squad system |
| slit/tv-npa54 | tv-npa54 | Economy management and worker allocation |
| toast/tv-nwnch | tv-nwnch | Resource denial behaviors for fighters |
| nux/tv-lzll | tv-lzll | Meaningful termination conditions |
| rictus/tv-lzll | tv-lzll | Meaningful termination conditions (duplicate) |

### Performance optimizations

| Branch | Issue | Commit Summary |
|--------|-------|----------------|
| coma/tv-z57pa | tv-z57pa | Optimize hot-path agent scans with spatial index |
| keeper/tv-hoess | tv-hoess | Incremental spatial index updates |
| warboy/tv-a5gd5 | tv-a5gd5 | Grid-local scans replacing O(n) loops |

### Terrain/rendering

| Branch | Issue | Commit Summary |
|--------|-------|----------------|
| capable/tv-luzl | tv-luzl | Water depth visualization |
| dementus/tv-i8zc | tv-i8zc | Cliff fall damage for elevation drops |
| dementus/tv-tm6sm | tv-tm6sm | Render ShallowWater in rivers |
| morsov/tv-gdlaj | tv-gdlaj | ShallowWater in TerrainCatalog |
| nux/tv-gjim | tv-gjim | Mud terrain type for swamp biomes |
| organic/tv-vopua | tv-vopua | Mud.png terrain sprite |
| rictus/tv-vgzm | tv-vgzm | Visual ramp tiles for elevation |
| dementus/tv-9ixk | tv-9ixk | Biome-specific resource gathering bonuses |
| capable/tv-fwrl | tv-fwrl | Mangonel AoE 5-tile range |
| rictus/tv-19cx | tv-19cx | Bear and wolf sprites |
| slit/tv-8p2s1 | tv-8p2s1 | Bear/wolf 8-orientation sprite refs |

### Refactoring/cleanup

| Branch | Issue | Commit Summary |
|--------|-------|----------------|
| capable/tv-lvcn | tv-lvcn | Remove vestigial aliases and dead code |
| dementus/tv-jfi6 | tv-jfi6 | Standardize needsPopCapHouse caching |
| dementus/tv-vu24a | tv-vu24a | Remove unused WallNone enum |
| rictus/tv-s7x7 | tv-s7x7 | Remove unused terrain type aliases |
| rictus/tv-shxf1 | tv-shxf1 | Clean up behavior code |
| slit/tv-cxxex | tv-cxxex | Cleanup spawn.nim |
| toast/tv-octv | tv-octv | Modularize AI with explicit imports |

### Docs

| Branch | Issue | Commit Summary |
|--------|-------|----------------|
| ace/tv-wmfno | tv-wmfno | Missing docs/README.md entries |
| coma/tv-qfd0j | tv-qfd0j | CONTRIBUTING.md guide |
| fury/tv-jd9 | tv-jd9 | Role audit report updates |
| keeper/tv-5j3qg | tv-5j3qg | architecture.md overview |
| morsov/tv-wvgw3 | tv-wvgw3 | Python API reference |
| nux/tv-4837 | tv-4837 | Include pattern documentation |
| nux/tv-x1l00 | tv-x1l00 | Audit merges for missing art |
| organic/tv-p12dp | tv-p12dp | README/docs update |
| warboy/tv-p12dp | tv-p12dp | README/docs update (duplicate) |
| angharad/tv-p10zl | tv-p10zl | Generate missing assets |

### Tests/fixes

| Branch | Issue | Commit Summary |
|--------|-------|----------------|
| coma/tv-d6m3x | tv-d6m3x | Training tests for production queue |
| keeper/tv-erda3 | tv-erda3 | Gitignore test binaries |
| nux/tv-e4sht | tv-e4sht | Patrol test difficulty fix |
| nux/tv-t78ct | tv-t78ct | Coordination/economy unit tests |
| nux/tv-tx67t | tv-tx67t | Remove fish when water→empty |
| nux/tv-l0oc | tv-l0oc | Builder priority reorder |
| nux/tv-minx5 | tv-minx5 | Fix action_space.md paths |
| rictus/tv-wisp-y1kfh | tv-wisp-y1kfh | Multi-builder bonus for walls |
| warboy/tv-t0ekp | tv-t0ekp | Remove tracked issues.jsonl |

### Conflict-resolution / duplicate branches (furiosa)

| Branch | Issue | Content |
|--------|-------|---------|
| furiosa/hq-cv-7j5mg | hq-cv-7j5mg | wonderVictoryCountdown fix (dup of tv-wisp-1rmd) |
| furiosa/hq-cv-oguds | hq-cv-oguds | wonderVictoryCountdown fix (dup of tv-wisp-1rmd) |
| furiosa/hq-cv-opc3q | hq-cv-opc3q | wonderVictoryCountdown fix (dup of tv-wisp-1rmd) |
| furiosa/hq-cv-pwcju | hq-cv-pwcju | wonderVictoryCountdown fix (dup of tv-wisp-1rmd) |
| furiosa/tv-wisp-1rmd | tv-wisp-1rmd | wonderVictoryCountdown fix (in refinery) |
| rictus/hq-cv-l5vdy | hq-cv-l5vdy | Remove dead wonderVictoryCountdown refs |

### Init branches (no issue)

| Branch | Notes |
|--------|-------|
| dementus-mkuhvi6z | 2 commits ahead, init branch |
| furiosa-mkuhtgy6 | 1 commit ahead, init branch |
| rictus-mkufq7yk | 1 commit ahead, init branch |
| rictus-mkuhn64r | 1 commit ahead, init branch |

## Duplicate Issue Work

Multiple branches working on the same issue (potential conflicts):

- **tv-lzll**: nux + rictus (both have "meaningful termination conditions")
- **tv-wisp-746p**: chumbucket + slit (both have "attack-move command")
- **tv-p12dp**: organic + warboy (both have "README/docs update")
- **tv-t74r7**: angharad + warboy (relic victory - angharad has full impl, warboy has relic drop fix)
- **tv-wisp-1rmd**: furiosa (x5 branches!) + refinery (already being processed)

## Recommendations

1. **Delete 41 merged branches** - no work at risk
2. **Delete 4 init branches** - no useful work (just sandbox init commits)
3. **Delete 5 furiosa/hq-cv-* branches** - tv-wisp-1rmd is already in refinery queue
4. **Delete refinery/tv-wisp-it6g** - empty, no commits ahead
5. **Triage ~92 orphaned feature branches** - these contain significant unmerged work including:
   - Multiple victory condition implementations
   - AI/behavior improvements
   - Performance optimizations
   - New gameplay features
6. **Resolve duplicate branches** before merging (tv-lzll, tv-wisp-746p, tv-p12dp, tv-t74r7)
