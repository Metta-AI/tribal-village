# Siege & Fortifications Plan (AoE2-lite)

Date: 2026-01-13
Owner: Design / Systems
Status: Complete

## Goals
- Make siege the clear, efficient answer to fortifications.
- Make walls destructible (no permanent hard blocks).
- Keep siege AI extremely simple and predictable.
- Add basic static defense via Guard Tower and armed Castle.

## Core Decisions (Locked)
- Wall HP: **10**
- Siege bonus vs buildings: **x3**
- Guard Tower range: **4**
- Castle range: **6**

## 1) Siege Units (Two-Building Approach)

### Design Note (Locked)
- One building = one unit type for training.
- Siege is split into three buildings:
  - **Siege Workshop** -> **Battering Ram**
  - **Mangonel Workshop** -> **Mangonel**
  - **Trebuchet Workshop** -> **Trebuchet**

### 1.1 Battering Ram
**Role:** Best vs structures, weak vs units.

**Training:** Siege Workshop.

**AI (very simple):**
1) On spawn, move forward in current orientation.
2) If blocked by any thing (unit/building/wall/door), attack that target.
3) If target is destroyed, resume moving forward.
4) If multiple candidates are adjacent, attack the nearest (tie-break arbitrary).

**Stats (initial target ranges):**
- HP: high
- Damage: low vs units
- Building damage: base damage * x3
- Range: 1

### 1.2 Mangonel
**Role:** Clump breaker; moderate vs buildings.

**Training:** Mangonel Workshop.

**Attack Shape:**
- “Large spear”: forward line length 4–5 tiles with 1‑tile side prongs.
- Essentially a longer spear AoE (extended prongs).

**AI (very simple):**
- If any enemy is hit by extended AoE in front, attack.
- Else move forward (same simple logic as Ram).

**Stats (initial target ranges):**
- HP: medium
- Damage: medium vs units
- Building damage: base damage * x3
- Range: 2–3 (effective through AoE)

## 2) Fortifications & Buildings

### 2.1 Destructible Walls
- Walls receive HP (10) and can be attacked like doors.
- Non‑siege damage is reduced vs walls (tune later if needed).
- Siege damage uses the x3 building multiplier.

### 2.2 Guard Tower (new building)
- Static ranged defender.
- Auto‑attacks nearest enemy in range 4.
- No advanced targeting, no micro.

### 2.3 Castle (existing building, armed)
- Static ranged defender with longer range (6).
- Higher HP than Guard Tower.

## 3) Combat Rules
- Buildings (Wall, Door, Outpost, Guard Tower, Castle, Town Center, Monastery) are attackable.
- Siege units (Ram, Mangonel, Trebuchet) do x3 damage vs buildings.
- Siege Engineers university tech adds +20% building damage for siege units.
- Masonry and Architecture university techs reduce incoming building damage by 1 each.
- Ranged towers and town centers use basic "nearest target in range" logic.

## 4) AI Rules (Simple, deterministic)
- Siege units:
  - Move straight until blocked.
  - Attack blocking target until destroyed.
  - Resume moving straight.
- Towers/Castle:
  - Each tick, attack nearest enemy in range.

## 5) Assets
- Add prompts for new sprites in `data/prompts/assets.tsv`:
  - `battering_ram.png`
  - `mangonel.png`
  - `guard_tower.png`
- If we want oriented siege sprites later:
  - `oriented/battering_ram.{dir}.png`
  - `oriented/mangonel.{dir}.png`

## 6) Implementation Milestones (first pass)
1) ~~Make walls destructible with HP=10.~~ (Done)
2) ~~Add building HP + attackability (doors + main fortifications).~~ (Done: Wall, Door, Outpost, GuardTower, Castle, TownCenter, Monastery are attackable)
3) ~~Add siege building damage multiplier (x3).~~ (Done: `SiegeStructureMultiplier = 3`)
4) ~~Add Guard Tower with range 4 and simple auto‑attack.~~ (Done)
5) ~~Arm Castle with range 6 and simple auto‑attack.~~ (Done)
6) ~~Add Siege Workshop (Ram) + Mangonel Workshop (Mangonel).~~ (Done: also TrebuchetWorkshop)
7) ~~Add Battering Ram unit + simple AI.~~ (Done)
8) ~~Add Mangonel unit + extended spear AoE + simple AI.~~ (Done)
9) Add Trebuchet unit with pack/unpack mechanic. (Done: `TrebuchetBaseRange = 6`, `TrebuchetPackDuration = 15`)
10) Add Scorpion (anti-infantry siege ballista). (Done: `ScorpionBaseRange = 4`)

## Known Issues

1. ~~**Battering ram targeting priority**~~ - FIXED: All siege units (BatteringRam, Mangonel, Trebuchet) now prioritize structures in `targetPriority()`.
2. **No repair mechanic** - Buildings cannot be healed once damaged. Villagers could be given a repair ability.
3. ~~**No garrison mechanic**~~ - IMPLEMENTED: Full AoE2-style garrison system with TC, Castle, Tower, and House garrison.
4. **Siege training visibility requirement** - Villagers must see enemy structures within ObservationRadius (5 tiles) to trigger siege training. May not activate fast enough during active combat.
