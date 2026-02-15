# Episode Audit Results (2026-02-15)

Baseline audit of two 3000-step episodes using `scripts/feature_audit.nim` with compile-time audit flags. Documents which implemented mechanics actually fire during gameplay.

## Summary

**Of ~150 implemented mechanics across 45 unit classes, 50+ building types, 30+ techs, and 5 victory modes, only a small fraction are exercised in 3000 steps.**

### Scorecard

| Category | Implemented | Fires | Coverage |
|----------|------------|-------|----------|
| Unit classes | 45 | 6 (Villager, ManAtArms, Scout, Archer, Monk, Boat) | **13%** |
| Building types | 50+ | ~22 core types | ~44% |
| Blacksmith upgrades | 15 tiers | 9-13 levels | **60-87%** |
| University techs | 10 | 0 | **0%** |
| Castle techs | 16 (2 per civ) | 0 | **0%** |
| Unit upgrades | 5 lines | 0 | **0%** |
| Economy techs | 12 | 4-6 (Wheelbarrow, Hand Cart only) | **33-50%** |
| Victory modes | 5 | 0 triggered | **0%** |
| Special mechanics | ~15 | ~5 | **33%** |

## What Works

### Economy (Good)
- Resource gathering active: Wood dominant, Food second, Gold/Stone low
- All teams build core economic buildings (Mill, LumberCamp, MiningCamp, Quarry, Granary)
- Market trading detected (price movement observed)
- Farm/Mill queues processing
- Resource stockpiles fluctuate with real income/spending flows
- All-time totals show 80-268 wood gathered, 0-121 food gathered per team

### Buildings (Good, but wall-heavy)
- Wall spam dominates: 393-856 walls per episode (60-70% of all buildings)
- Houses built consistently (~28-30 per team)
- Outposts built (54-110 total)
- Mills built (48-65 total, some teams build 14-27)
- Military buildings built: Barracks (5-6), Stables (3-5), Archery Ranges (2-4)
- Support buildings: Monasteries (2-6), Markets (2-9), Universities (6-7)

### Military (Partial)
- ManAtArms: 56-74 trained per episode (first at step ~837-866)
- Scouts: 30-42 trained (first at step ~1021-1095)
- Archers: 10-11 trained (first at step ~682-1030)
- Combat deaths: 215-349 per episode (real fighting happening)
- AI role split: ~330 Gatherer / ~336 Builder / ~328 Fighter

### Blacksmith (Good)
- 9-13 upgrade levels researched per episode
- Melee Attack L1 most common (4-5 teams)
- Archer Attack L1 researched by 2-3 teams
- Armor tiers (Infantry, Cavalry, Archer) researched by 1-2 teams
- One team reached Melee Attack L2
- First blacksmith research at step ~401-654

### Economy Techs (Partial)
- Wheelbarrow researched by 3-5 teams (first at step ~11-141)
- Hand Cart researched by 1-2 teams (step ~621-2928)
- No farming techs (Horse Collar, Heavy Plow, Crop Rotation)
- No mining/lumbering techs (Double Bit Axe, Gold Mining, etc.)

## What Never Fires

### University Techs (0/10)
Buildings exist (6-7 universities built) but AI never researches:
- Ballistics, Murder Holes, Masonry, Architecture
- Treadmill Crane, Arrowslits, Heated Shot
- Siege Engineers, Chemistry, Coinage

### Castle Techs (0/16)
No castles with civ techs researched. Zero unique civ tech usage.

### Unit Upgrades (0/5 lines)
No tier progression:
- ManAtArms never upgrades to Longswordsman/Champion
- Scout never upgrades to Light Cavalry/Hussar
- Archer never upgrades to Crossbowman/Arbalester
- Skirmisher line never trained
- Cavalry Archer line never trained

### Advanced Units (0 trained)
| Unit Category | Units | Trained |
|---------------|-------|---------|
| Heavy Infantry | Longswordsman, Champion | 0 |
| Heavy Cavalry | Knight, Cavalier, Paladin | 0 |
| Counter units | Skirmisher, Camel, Huskarl | 0 |
| Siege | Ram, Mangonel, Trebuchet, Scorpion | 0 |
| Naval combat | Galley, Fire Ship, Demo Ship, Cannon Galleon | 0 |
| Unique units | Samurai, Longbowman, Cataphract, etc. | 0 |
| Gunpowder | Hand Cannoneer, Janissary | 0 |
| Trade | Trade Cog | 0 |
| Transport | Transport Ship | 0 |

### Victory Conditions (0 triggered)
- All 8 kings alive at step 3000
- No wonder built
- Relics on map (16-17) but none garrisoned in monasteries
- No KOTH control point contested
- No conquest (no team eliminated)

### Other Missing Mechanics
- **Monk conversion**: 0-3 monks trained, no conversions observed
- **Garrison**: Not audited but likely minimal
- **Tribute**: No inter-team resource transfer
- **Naval economy**: 0-1 docks, 0-1 boats, no fishing ships or trade cogs
- **Relic collection**: Monasteries built but relics not picked up
- **Altar capture**: Not observed
- **Embark/disembark**: No transport ships
- **Trebuchet pack/unpack**: No trebuchets
- **AoE damage (Mangonel)**: No mangonels

## Economy Details (from econAudit)

### All-Time Resource Totals (Episode 2, seed varies)
| Team | Food Gained | Wood Gained | Gold Gained | Stone Gained |
|------|-------------|-------------|-------------|--------------|
| RED | 121 | 264 | 46 | 10 |
| ORANGE | 42 | 124 | 6 | 5 |
| YELLOW | 31 | 219 | 12 | 0 |
| GREEN | 2 | 80 | 1 | 0 |
| MAGENTA | 54 | 145 | 5 | 9 |
| BLUE | 0 | 255 | 0 | 0 |
| GRAY | 0 | 87 | 0 | 0 |
| PINK | 58 | 258 | 16 | 0 |

**Key insight**: Wood gathering massively outpaces all other resources. Gold is scarce (0-46 total). Stone nearly zero for most teams. Food moderate. This explains why advanced techs/units (which cost gold) never appear.

### Action Distribution (from actionAudit, end-of-episode)
Typical team breakdown: ~80% move, ~13% noop/idle, ~3-4% build, <1% attack

## Root Cause Analysis

### Why advanced mechanics don't fire:

1. **Gold starvation**: Advanced units cost gold (Knight: 3F/2G, Paladin: 6F/4G). Teams gather 0-46 gold total. Can't afford anything beyond ManAtArms.

2. **No economy tech progression**: Without Double Bit Axe, Gold Mining, Horse Collar, gathering rates stay at base. Economy never accelerates.

3. **University dead zone**: AI builds universities but has no behavior to research there. Code path exists but AI never triggers it.

4. **Castle tech blind spot**: Same as university — buildings built, research never initiated.

5. **Unit upgrade ignorance**: AI trains ManAtArms but never upgrades to Longswordsman. Upgrade cost (3F/2G) is affordable but AI doesn't prioritize it.

6. **Wall obsession**: ~80% of construction is walls. AI over-invests in static defense, under-invests in military buildings and unit production.

7. **3000 steps may be too short**: First military units appear at step 682-1095. Advanced techs/units might need 5000-10000 steps. But the slow economy suggests even more steps won't help without balance changes.

## Recommendations

### High Priority (unlock mechanic usage)
1. **Increase gold gathering rate or gold availability** — current gold income is 10-50x too low for the tech tree
2. **AI: add University research behavior** — buildings exist, just need research triggers
3. **AI: add unit upgrade behavior** — ManAtArms→Longsword should happen automatically
4. **Reduce wall building priority** — cap wall count or reduce AI wall preference

### Medium Priority (deepen existing mechanics)
5. **AI: add economy tech research** — Horse Collar, Double Bit Axe, Gold Mining
6. **AI: add Castle tech research** — civ-unique tech behavior
7. **AI: train diverse unit types** — Skirmishers, Knights, Cavalry Archers
8. **Increase episode length for audits** — test 5000-10000 steps

### Low Priority (polish)
9. **Relic collection behavior** — monks pick up and garrison relics
10. **Naval AI** — dock building, fishing, naval combat
11. **Victory condition pursuit** — AI actively works toward a victory type
12. **Tribute/alliance mechanics** — inter-team economy
