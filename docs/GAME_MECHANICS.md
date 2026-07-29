# Game Mechanics                                                {#game_mechanics}

A specification of *Betrayal at Krondor*'s gameplay systems, described in game
terms and precise enough to reimplement from. Only the **rest and fatigue**
system is documented so far; the other systems have not yet been investigated.

## Sleep & Fatigue                                              {#mech_fatigue}

Party members tire as they travel. What counts is the time **since the party
last rested**, not the total time spent awake: any rest resets that clock to
zero, so fatigue never carries over from one leg of travel to the next.

### Warning and exhaustion

| Time since last rest | Effect |
|---|---|
| Under 17 hours | No effect. |
| 17 hours | A companion warns the party to rest. No loss yet. |
| 18 hours and beyond | Each active member loses reserve points every hour (see rates). The warning repeats each hour until the party rests. |

The loss repeats every hour, so traveling indefinitely without rest eventually
knocks out the whole party.

Warning line: *"'We need rest,' he said, looking for a good place to camp. 'If
we go much further without sleep, we might not be able to handle any unexpected
surprises on the road.'"*

Because the warning always arrives a full in-game hour before any loss begins,
and **any** rest — even a single hour — resets the clock completely, a party
that makes camp when warned never takes fatigue damage. Camping needs a safe
spot and is refused with enemies nearby.

### Fatigue drain rate

Once exhausted, each active member loses this many reserve points **per hour**,
by character — reflecting each character's constitution:

| Character | Loss per hour |
|---|---:|
| Gorath | 1 (hardiest) |
| Locklear | 2 |
| Owyn | 2 |
| Pug | 2 |
| James | 2 |
| Patrus | 3 (frailest) |

### The Health / Stamina reserve

Each character's Health and Stamina together form a single reserve that fatigue
and combat draw down:

- **Stamina is spent first** — the non-lethal buffer that absorbs fatigue and
  lighter blows.
- **Health falls only once Stamina is gone** — the lethal remainder.
- Healing works in the opposite order: it refills Health to full before topping
  up Stamina.

If a character's reserve reaches zero they **collapse** (unconscious, near
death): held at the brink, taking no further part until healed. If the entire
active party collapses, the party is incapacitated.

### Recovery through rest

Resting stops the fatigue clock and refills the reserve.

- **Recovery rate:** about **1 reserve point per hour** per member (faster while
  a character is under a healing effect). Recovering N points therefore takes
  roughly N in-game hours of rest.
- **Camp** (on the road): refills the reserve up to **80%** of its maximum. The
  party may set a wake-up hour, or sleep until every member is healed (all at
  80%). Camping is not allowed with enemies nearby.
- **Inn:** refills the reserve to **100%**, for a fee, resting through to a
  chosen hour.

Resting also passes time normally: it gradually cures illness and consumes the
party's rations as the days pass.
