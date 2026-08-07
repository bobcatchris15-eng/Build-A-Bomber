# Economy Balance

Measured 2026-08-07. The numbers here are what `harvester_fsm.gd`'s constants
were set from, and what `tests/battle/test_economy_balance.gd` pins.

## The target

Chris's spec, stated as a ratio so it can be measured rather than argued about:

> A normal economy — one refinery and four harvesters — should grow its
> resources on hand with ONE manufactory running continuously, and probably do
> 80% of keeping up with two manufactories running continuously.

## The draw side is a constant, and that is the key fact

`DesignCosting.build_time_for_cost()` is `(metal + 2 × crystal) × 0.05`, and the
drip-feed in `ProductionService._tick_queue()` spends the whole cost across
exactly that time. So a running queue draws:

```
(m + 2c) / ((m + 2c) × 0.05)  =  20 cost-units per second
```

**Regardless of what is being built.** A scout car and a heavy tank drain the
bank at the same rate; the tank just does it for longer. Verified against five
bundled designs, all exactly 20.0/s.

Only the clamps break it — `clampf(..., 3.0, 40.0)` — so designs under ~60 or
over ~800 cost-units draw more or less than 20. None of the bundled ones do.

That collapses the spec to a single number:

| | draw | requirement |
|---|---|---|
| One line | 20/s | income > 20/s |
| Two lines | 40/s | income ≈ 0.8 × 40 = **32/s** |

32/s satisfies both, with 60% headroom on the one-line case.

## The income side, measured

`tools/probe_economy_balance.gd` — a real match on `open_plains`, 4 harvesters,
1 refinery, production idle, 30 s warm-up then 180 s averaged off the ledger.

**Before:**

```
capacity 50, chunk 25/3.0s, unload 0.6s
metal 5.28/s, crystal 7.22/s -> INCOME 19.72 cost-units/s  (4.93 per harvester)
one line  (draw 20/s): SHRINKS  - net -0.3/s
two lines (draw 40/s): keeps up 49%   (target 80%)
```

So the economy could not sustain even a *single* production line, which is why
the AI reached three harvesters and never fielded a combat unit — it was not a
decision bug, it was arithmetic. Needed ×1.62.

**After (first pass, two pools, nearest-node targeting):**

```
capacity 80, chunk 40/3.0s, unload 0.6s
metal 7.11/s, crystal 12.44/s -> INCOME 32.00 cost-units/s  (8.00 per harvester)
one line  (draw 20/s): GROWS  - net +12.0/s
two lines (draw 40/s): keeps up 80%   (target 80%)
```

**After (final, resource fields + value-weighted targeting):**

```
capacity 56, chunk 28/3.0s, unload 0.6s
metal 7.18/s, crystal 12.22/s -> INCOME 31.63 credits/s  (7.91 per harvester)
one line  (draw 20/s): GROWS  - net +11.6/s
two lines (draw 40/s): keeps up 79%   (target 80%)
```

The hopper came back DOWN from 80 to 56 because harvesters that chase credits
rather than metres earn ~37% more from the same fleet. Same target, richer
trucks, smaller hoppers.

## THE AGGREGATE IS A LIE, AND THIS IS THE REAL FINDING

Everything above measures `metal + 2 × crystal`. That model assumes the two
pools are **fungible**, and they are not — you cannot pay a metal bill with
crystal. Split them and the picture inverts:

| | income | one line's draw | keeps up |
|---|---|---|---|
| **metal** | 7.11/s | 15.56/s | **46%** |
| **crystal** | 12.44/s | 2.22/s | **560%** |

Designs are metal-hungry and crystal-light — mean draw across eight bundled
designs is 15.56 metal/s against 2.22 crystal/s, an 87:13 split. The maps supply
roughly 70:30. Actual delivered income came in at 36:64, because harvesters go to
the *nearest* node and the crystal happens to sit closer on `open_plains`.

So the honest verdict on the spec is: **not met.** The economy cannot sustain
even one production line on metal, while crystal accumulates uselessly. The
aggregate reached 32/s only because it valued a surplus resource at double.

This is what the AI was dying of. After the queue fix below it correctly reaches
for a Breaker TD — and then sits `stalled=true` at 0 metal with 155 crystal
banked, for the rest of the match.

**STILL TRUE after the resource-fields pass, and still deliberately unpatched.**
`ResourceCatalog.deliver_value()` now makes one credit worth one cost-unit
whichever pool it lands in, so the *aggregate* is honest — but there are still
two pools, and metal is still the binding one at ~46% of a line while crystal
runs a large surplus.

Chris redirected the economy to a single "credits" pool on 2026-08-07 and chose
to prototype the resource fields first. That conversion is what closes this:
merging the pools makes the aggregate the only number, and every consumer already
reads `ResourceCatalog.credits()`. Rebalancing the metal:crystal mix in between
would be work thrown away.

## Why both constants had to move together

A round trip is ~10.1 s on `open_plains`: ~6 s extracting (2 cycles × 3 s), 0.6 s
unloading, ~3.5 s driving.

Raising **capacity alone** does nothing. An 80-unit hopper at the old 25/cycle
rate takes 4 cycles — 12 s — so the trip stretches to 16.1 s and delivers
80/16.1 = 4.97 per second. That is *identical* to the old 50/10.1 = 4.95. The
change would have looked like a buff and measured as nothing.

Scaling the chunk with the hopper keeps the cycle count (and the visible rhythm
at the patch) fixed, so the extra capacity is pure throughput. Both went ×1.6.

Raising **extraction alone** cannot reach the target either: the floor is one
cycle, giving a 7.1 s trip and ×1.42.

## The hopper is now a property of the design

It was a flat 50 for every unit — in a game whose entire premise is that you
design the units, a purpose-built ore hauler carried exactly as much as a scout
car with a harvester arm bolted on.

```
capacity = 56 × harvester_modules × tier_multiplier
tier:  light 0.7   medium 1.0   heavy 1.5
```

Extraction scales by the same factors, so fill *time* is constant across designs.
A heavier hauler makes fewer trips for the same ore, paid for in metal, weight
and speed — not in a longer dwell at the patch.

| design | hopper |
|---|---|
| light hull, 1 module | 39 |
| medium hull, 1 module (the bundled Ore Trucker) | 56 |
| heavy hull, 1 module | 84 |
| medium hull, 2 modules | 112 |

## Re-measuring

```bash
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tools/probe_economy_balance.gd
```

Four minutes, because it drives a real map with real travel. The arithmetic half
is asserted in milliseconds by `tests/battle/test_economy_balance.gd`, which is
what catches a constant being edited without the consequence being noticed.

## The AI queue bug this pass uncovered

Separate from the arithmetic, and it survived the economy being fixed.

`Commander.read_state()` counted only **live** harvesters. A truck that was paid
for and 90% built did not exist yet, so `EXPAND_ECONOMY` kept scoring highest and
kept queueing more. The depth cap (`AI_MAX_QUEUE_DEPTH = 2`) then filled
permanently with harvesters, and every `ai_build_unit()` call for a combat design
was refused at the door because that queue was full.

Measured before the fix: the medium queue sat at depth 2 with an Ore Trucker at
its head for the entire match, the commander chose `BUILD_GENERAL` 3,702 times,
and **zero combat units were ever enqueued** — let alone produced. It read as an
economy problem for weeks. `read_state()` now counts in-flight production, and
the AI reaches a Breaker TD within ~3,600 ticks.

**Result over a full 7,200-tick probe: `combat=2`, up from `combat=0`.** The AI
fields an army for the first time in this rebuild's history. Two units in seven
minutes is still starvation pace — that is the metal-vs-crystal problem above,
not this one — but the door is open where before it was bolted shut.

## The resource rework (2026-08-07)

Four gatherable types, differing by **value density and location** — any
harvester works any field, so the decision is where to send trucks:

| resource | credits/unit | field | respawn | where |
|---|---|---|---|---|
| lumber | 1.0 | 9 seedlings, 11 m | 20 s | close to each base |
| ore | 1.5 | 7 rocks, 9 m | 35 s | the staple, mid-map |
| crystal | 3.0 | 5 clusters, 8 m | 50 s | scarcer, further out |
| oil | 4.0 | 1 well | 25 s | contested centre line |

Every map entry is now a **field centre** rather than a lump — the schema did not
change, so all ten maps and the fairness lint carried over untouched. Everything
is renewable: a mined-out collectible is removed and the field puts a fresh one
back.

### Value-weighted targeting, and why it was mandatory

Node selection scored distance, crowding and pool shortage — but never **value**.
With lumber authored close to each base (deliberately, as the safe opening
income), pure nearest-node targeting sent every truck to lumber and nothing else:
**crystal income measured exactly 0.00/s** across a three-minute run. The cheapest
resource on the map won every contest because it was the closest, which is the
precise opposite of the design.

`nearest_resource_node()` now divides distance by relative value, so oil reads at
~0.4× its true distance and lumber at 1.5×. A truck will drive past a tree to
reach a well, which is the whole point.

## Notes

**Travel is map-dependent and `open_plains` is not the worst case.** A map with
distant ore lengthens the trip and lowers income against the same constants.
Treat 32/s as the figure for a short-haul map, and the two-line ratio as
something that degrades with haul distance — which is a map balance lever, not a
bug.
