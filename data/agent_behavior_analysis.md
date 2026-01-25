# Tribal Village Agent Behavior Analysis

## Executive Summary

Analysis of scripted AI roles in tribal-village reveals a well-structured hierarchical behavior system with three primary roles (Gatherer, Builder, Fighter) using priority-based option selection. The AI demonstrates high success rates (90-94%) across all roles, with movement being the dominant action type.

## Role Architecture

### Role Assignment
- Agents are assigned roles based on their slot ID modulo 6:
  - Slots 0-1: Gatherer (resource collection focus)
  - Slots 2-3: Builder (construction focus)
  - Slots 4-5: Fighter (combat/defense focus)
- Teams operate independently with ~42 agents per team

### Options Framework
Each role uses a priority-ordered list of "OptionDefs" with:
- `canStart`: Precondition check
- `shouldTerminate`: Termination condition
- `act`: Execution logic returning encoded action
- `interruptible`: Whether higher-priority options can interrupt

## Gatherer Behavior Patterns

### Priority Order
1. **PlantOnFertile** - Plant wheat/wood on fertile tiles
2. **MarketTrade** - Exchange resources at market
3. **CarryingStockpile** - Return resources to base
4. **Hearts** - Prioritize altar heart collection (gold->magma->bar->altar)
5. **Resource** - Gather wood/stone/gold based on team stockpile needs
6. **Food** - Gather wheat, hunt animals, fish
7. **Irrigate** - Spread water to create fertile tiles
8. **Scavenge** - Collect from skeletons
9. **StoreValuables** - Store items in blacksmith/granary/barrel
10. **FallbackSearch** - Spiral search pattern

### Task Selection Logic
Gatherers dynamically choose tasks based on:
- Hearts priority if altar has <10 hearts
- Otherwise, gather the resource with lowest stockpile count

## Builder Behavior Patterns

### Priority Order
1. **PlantOnFertile** - Plant if carrying wheat/wood
2. **DropoffCarrying** - Return any carried resources
3. **PopCap** - Build houses when at population limit
4. **CoreInfrastructure** - Build Granary, LumberCamp, Quarry, MiningCamp
5. **MillNearResource** - Build mill near wheat/fertile areas
6. **PlantIfMills** - Plant after establishing mills
7. **CampThreshold** - Build resource camps near resource clusters
8. **WallRing** - Construct defensive wall ring around altar
9. **TechBuildings** - Build tech structures (Loom, Oven, Blacksmith, etc.)
10. **GatherScarce** - Help gather scarce resources
11. **MarketTrade** - Trade at market
12. **VisitTradingHub** - Visit neutral trading hubs
13. **SmeltGold** / **CraftBread** / **StoreValuables**
14. **FallbackSearch** - Spiral search

### Building Priorities
- Core infrastructure (camps) comes early
- Wall rings built after lumber camp established
- Tech buildings built after walls

## Fighter Behavior Patterns

### Priority Order
1. **Breakout** - Escape when fully enclosed
2. **Retreat** - Flee when HP < 33%
3. **Monk** - Monk-specific relic collection
4. **DividerDefense** - Build defensive wall dividers toward enemies
5. **Lanterns** - Place/maintain lantern network
6. **DropoffFood** - Return food to base
7. **Train** - Train units at military buildings
8. **MaintainGear** - Get armor/spears from blacksmith
9. **HuntPredators** - Kill bears/wolves if healthy
10. **ClearGoblins** - Destroy goblin structures
11. **SmeltGold** / **CraftBread** / **StoreValuables**
12. **Aggressive** - Hunt tumors, spawners, animals
13. **FallbackSearch** - Spiral search

### Combat Decisions
- Attacks are opportunity-based via `findAttackOpportunity()`
- Attack priority: Tumors > Spawners > Enemy Agents > Structures
- Range varies by unit class (Archer, Mangonel, etc.)

## Movement Patterns

### Spiral Search
- Agents use incremental spiral search from their base position
- Clockwise/counter-clockwise alternates based on agent ID
- Spiral advances 3 steps at a time for faster coverage
- Resets after 100 arcs to continue from current area

### Anti-Oscillation
- Recent positions tracked in 12-position ring buffer
- Escape mode triggered if stuck in 1-3 tiles for 10+ steps
- Blocked move direction remembered for 4 steps

### Pathfinding
- A* pathfinding for distances >= 6 tiles
- Explored node limit of 250 to prevent over-computation
- Falls back to direct movement for short distances

## Entity Interactions

### Building Usage
- Resources deposited at specialized buildings (Granary, LumberCamp, etc.)
- Training at military buildings (Barracks, ArcheryRange, etc.)
- Crafting at production buildings (ClayOven, Blacksmith, etc.)
- Market trading when resource imbalances exist

### Resource Collection
- Resources found via spiral search with caching
- Closest known positions cached and validated
- Multiple resource types supported (food, wood, stone, gold, water)

## Performance Metrics

### Action Distribution
| Role     | Move  | Attack | Use   | Build | Invalid |
|----------|-------|--------|-------|-------|---------|
| Gatherer | 90.5% | 2.8%   | 0.8%  | 0.0%  | 3.5%    |
| Builder  | 86.9% | 2.9%   | 0.8%  | 0.5%  | 5.9%    |
| Fighter  | 85.9% | 4.5%   | 0.3%  | 0.1%  | 7.2%    |

### Success Rates
- Gatherer: 94.1%
- Builder: 91.2%
- Fighter: 90.9%

### Development Timeline (typical game)
- Steps 0-100: Initial house building, heart collection begins
- Steps 100-200: Rapid house expansion, all teams reach 10 hearts
- Steps 200-300: Houses reach maximum (32), infrastructure complete
- Steps 300+: Maintenance phase, combat/resource collection continues

## Key Observations

1. **Movement Dominance**: 85-90% of all actions are movement, indicating highly mobile agents
2. **Role Specialization**: Each role has distinct priorities but shares fallback behaviors
3. **Adaptive Task Selection**: Gatherers dynamically switch tasks based on team needs
4. **Defensive Posture**: Fighters prioritize lantern networks and wall building
5. **Economic Balance**: All teams achieve similar development milestones
6. **Invalid Action Rate**: Higher for Fighters (7.2%) due to complex pathfinding
