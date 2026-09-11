# AI PLayer difficulty

## Passive
 - Focus on building and defending.
 - never attack or builds military units.
 - never builds defense buildings (towers).
 - can build gates and walls.
 - never ages up past age 2.

## Easy (default)
 - Focus on building and defending.
 - can attacks after 10min game time followed by random follow-up attacks.
 - can age up to age 2.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers max 1).

## Normal
 - Focus on building and defending.
 - can attacks after 7min game time followed by random follow-up attacks.
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

## The attack clock is longer than a King of the Hill match

**Open question as of 2026-09-11, no decision taken.** A bot goes to its station only
once its attack rule has fired, so the difficulty clock above currently gates the
turtle and the hill as well as the attack:

| Difficulty | First commit | Guards its dragon | Contests a 5-minute hill |
|---|---|---|---|
| Passive | never — it has no attack rule | never | never |
| Easy (default) | 10 min | after 10 min | no |
| Normal | 7 min | after 7 min | no |
| Hard | when the eco is up — 12 villagers, mill, barracks, 8 swordsmen | when that lands | unlikely |
| Unfair | when the eco is up — 10 villagers, barracks, 6 swordsmen | when that lands | unlikely |

King of the Hill is won at 9,000 points and a player holding the hill alone scores 3
a tick, so **the fastest possible match is 5 minutes** — half of Easy's first commit.
A playtest on 2026-09-11 ended 9,000 to 0: the bot never set foot in the zone for a
single tick, because it was still waiting for ten o'clock.

Trophy has the sharper version of the same problem. Passive's stated focus is
*"building and defending"* and it never attacks, so under the current rule it never
guards its dragon at all — the one unit whose death loses it the game.

The reading that resolves both: **walking onto neutral ground is not an attack, and
standing on your own dragon is not an attack.** The clock is about aggression against
another player, so it should gate the Last Man Standing branch and not the other two.
That would let a Passive bot turtle, which is what Passive means.