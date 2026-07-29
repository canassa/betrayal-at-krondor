# Game Mechanics                                                {#game_mechanics}

The player-facing rules of *Betrayal at Krondor* — what the game does, described
independently of how the engine implements it. Each section carries a stable
anchor (`{#mech_*}`) so code documentation can link to the rule it implements
with `@ref`.

## Sleep & Fatigue                                              {#mech_fatigue}

Party members tire as they travel. The game tracks how long it has been since
the party last rested: nothing happens for the first stretch, but pressing on
without sleep eventually wears the characters down.

**Warning.** After **17 hours** of travel without rest, a companion speaks up —
*"We need rest… if we go much further without sleep, we might not be able to
handle any unexpected surprises on the road."* — a prompt to make camp.

**Exhaustion.** After **18 hours** without rest, each **active** party member
begins losing **1–3 points per hour** from their combined Health/Stamina
reserve. The rate is per character: hardier members (e.g. Gorath) lose the
least, frailer ones (e.g. Patrus) the most. The loss repeats every hour until
the party rests. A member whose reserve reaches zero **collapses** (the
*Near-death* condition), and if the whole party goes down they are
incapacitated.

**Health & Stamina.** A character's Health and Stamina act as a single reserve.
Stamina is spent first — it is the non-lethal buffer that absorbs fatigue and
lighter blows — and only once it is gone does Health, the lethal remainder,
begin to fall.

**Recovery.** Resting clears the exhaustion timer and refills the reserve at
about **1 point per hour** per member (faster while a character is under the
*Healing* condition). How full a rest gets depends on where it is taken:

- **Camp** (on the road) restores the reserve up to **80%** of maximum. You can
  set a wake-up hour on the camp clock, or sleep until everyone is healed. You
  cannot camp with enemies nearby.
- **Inns** restore the reserve to **100%**, for a fee, resting through to a
  chosen hour.

Resting also passes time normally: it cures the *Sick* condition gradually,
lets other conditions run their course, and consumes the party's rations as the
days pass.

## Combat                                                       {#mech_combat}

_To be documented._

## Skills                                                       {#mech_skills}

_To be documented._
