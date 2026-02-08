# AI Profiling: 3000-Step Headless Episode

Date: 2026-02-16
Owner: Engineering / Analysis
Status: Active

## Run config
- Command: `TV_PROFILE_STEPS=3000 nim r -d:release --path:src /tmp/tv_behavior_profile.nim`
- Steps: 3000
- Seed: 42
- Controller: BuiltinAI
- Mode: headless (no renderer)

## Action summary
Total actions: 2,889,444

| Action | Count | Share |
| --- | --- | --- |
| move | 2,527,277 | 87.47% |
| invalid | 296,332 | 10.26% |
| attack | 53,855 | 1.86% |
| use | 9,776 | 0.34% |
| build | 1,878 | 0.06% |
| plant | 326 | 0.01% |
| plant_resource | 0 | 0.00% |
| swap | 0 | 0.00% |
| put | 0 | 0.00% |
| orient | 0 | 0.00% |
| noop | 0 | 0.00% |

## Building coverage
Baseline (spawned at step 0):
- TownCenter: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- House: t0=5 t1=5 t2=5 t3=4 t4=5 t5=4 t6=5 t7=4
- Granary: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- LumberCamp: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- Quarry: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- MiningCamp: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1

Max counts reached by end of episode:
- House: t0=32 t1=32 t2=33 t3=32 t4=32 t5=32 t6=32 t7=32
- Outpost: t0=16 t1=16 t2=17 t3=4 t4=33 t5=43 t6=6 t7=5
- Barracks: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- ArcheryRange: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- Stable: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- SiegeWorkshop: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- MangonelWorkshop: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- Blacksmith: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- Market: t0=2 t1=1 t2=2 t3=0 t4=2 t5=2 t6=1 t7=0
- Monastery: t0=1 t1=1 t2=1 t3=0 t4=1 t5=1 t6=1 t7=0
- Castle: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- ClayOven: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- WeavingLoom: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1

Unchanged from baseline:
- TownCenter: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- Granary: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- LumberCamp: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- Quarry: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1
- MiningCamp: t0=1 t1=1 t2=1 t3=1 t4=1 t5=1 t6=1 t7=1

Not observed (max stayed 0):
- GuardTower
- Dock
- Temple
- University
- Mill

## Notes
- Planting resources (action 7) did not occur in this episode.
- Non-move verbs remain rare compared to movement and invalid actions.
