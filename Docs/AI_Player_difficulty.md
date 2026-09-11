# AI PLayer difficulty

## Passive
 - Focus on building and defending.
 - never attack or builds military units.
 - never builds defense buildings (towers).
 - can build gates and walls.
 - never ages up past age 2.

## Easy (default)
 - Focus on building and defending.
 - can attacks after 5min game time followed by random follow-up attacks.
 - can age up to age 2.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers max 1).

## Normal
 - Focus on building and defending.
 - can attacks after 3.5min game time followed by random follow-up attacks.
 - can age up to age 3.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers max 5).

## Hard
 - Focus on strong economy followed by continues attacks.
 - can attacks after eco has been established.
 - can age up to age 4.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers, castles).

## Unfair
 - starts with 8 villagers and 2 swordsmen and 1 scout.
 - Focus on strong economy followed by continues attacks.
 - can attacks after eco has been established.
 - can age up to age 4.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers, castles).

# Game type — where the army is sent

Difficulty decides **when** a bot commits its army and how big that army has to be
first. The game type decides **where** that army goes. Every difficulty follows the
same blueprint, and no difficulty has its own copy of it — the bot asks the world
what match this is.

| Game type | The army is sent to | It is doing |
|---|---|---|
| Last Man Standing | the nearest enemy | attacking |
| Trophy | its own dragon | guarding |
| King of the Hill | the hill | occupying |
| Scenario | the nearest enemy | attacking |

 - **Trophy is a turtle.** There is no separate guard order and none is needed: a
   military unit defaults to Defensive stance, which makes it fight anything within
   5 tiles of where it stands and walk back afterwards. So standing on the dragon
   *is* guarding it.
 - **King of the Hill is an occupation, not a fight.** Standing inside the zone is
   exactly what scores, so the move order and the win condition are the same act.
 - A bot guards **its own** dragon, never somebody else's.
 - Idle soldiers are sent back to the station, not back at the enemy — otherwise the
   bot would walk away from what it is holding and never come back. Soldiers already
   on station are left alone.
 - If a match failed to place a trophy or a hill, that bot **attacks instead**: an
   unarmed match is decided by elimination, so turtling would mean standing still in
   a match being settled by a rule it was ignoring.

## When the army commits — the clock, per game type

The army is committed by the attack rule, so the clock in each difficulty above is
what decides when the bot leaves home. **That is a conquest clock, and three of the
four game types are not conquest**, so a difficulty may give a game type its own.

| Difficulty | Last Man Standing / Scenario | Trophy | King of the Hill |
|---|---|---|---|
| Passive | never — it has no attack rule, and never trains a soldier | — | — |
| Easy (default) | 5 min | at once | 1.5 min |
| Normal | 3.5 min | at once | 1 min |
| Hard | when the eco is up — 12 villagers, mill, barracks, 8 swordsmen | ← same | ← same |
| Unfair | when the eco is up — 10 villagers, barracks, 6 swordsmen | ← same | ← same |

 - The game-type clock **replaces** the difficulty's own, rather than being added to
   it: a game type is allowed to commit *earlier* than the opening, which is the
   whole reason it exists.
 - **The army-size condition is untouched by any of this.** Easy still needs five
   swordsmen in hand before it goes anywhere, so "at once" means *as soon as it has
   an army*, not "send the starting scout".
 - Hard and Unfair have no clock to move — they commit when the economy gate lands,
   in every mode — so they declare none, and their table row is the same in all four.
 - It only moves **aggression**. Everything else a bot does — gathering, building,
   ageing — is untouched by the game type.

**Why Trophy is "at once" at every level.** The thing it guards can be killed in the
first minute, so a handicap expressed as *"leaves its dragon alone for five minutes"*
is not a difficulty, it is a different loss condition. Guarding is defending, which is
the stated focus of every level on this page.

**Why King of the Hill needed its own number at all.** A hill match is won at 9,000
points and a side holding the hill alone scores 3 a tick, so **the fastest possible
match is 5 minutes** — which was Easy's first commit *after* the halving, and half of
it before. A playtest on 2026-09-11 ended 9,000 to 0: the bot never set foot in the
zone for a single tick, because it was still waiting for ten o'clock. A bot whose
clock is longer than the match cannot lose the hill — it can only fail to turn up.

*Ruled by the project owner on 2026-09-11: halve every attack clock, then a per-mode
clock in each profile for granular tuning. The knob is `mode_after_ticks` in
`game/data/ai_<level>.json`, and a test refuses any value that would let a bot arrive
after its own hill match can be over.*