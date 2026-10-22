# Monetization plan

Nothing here is built. No real purchases exist in the game yet; this is the plan for when the
game has players. The ids live in `Config.Monetization` (zero means "not configured").

## The rule

Sell looks, comfort and time with friends. Never sell the thing that makes the dark scary:
sweep charges, revives, seeing monsters, or skipping a level. A paid player and a free player
in the same party should face the same dark. That keeps co-op fair, keeps reviews kind, and
fits Roblox's guidance on fair monetization.

## What players work towards for free (built)

- **The scanner** starts weak (260 dots a second, 65 studs, a coarse sweep, a narrow cone). Static from every
  run buys Emitter, Range Coil, Sweep Grid and Phosphor at the workbench.
- **The battery**: sweeps cost charges found as battery cells in the maze. Capacitor, Spare
  Cell and Trickle Charger make the battery better.
- **Tools**: Quiet Shutter, Wide Lens, Pulse Radar, Echo Beacon, Wayfinder, Soft Soles.
- **Cosmetics for Static**: three dot tints and two gun housings.
- **Daily**: one shared seed a day with a leaderboard, and a visit streak.
- **Story**: hidden objects, tapes, manual pages, two endings, the endless Relay.

## What could be sold, in order of value and safety

| # | What | Type | Why it is safe | Hook in code |
| --- | --- | --- | --- | --- |
| 1 | **Premium Payouts** | Roblox pays by Premium players' play time | Costs players nothing. Every retention system above feeds it | None needed |
| 2 | **Phosphor packs**: dot tints and dot shapes that only Robux buys (ember, ice, a slow colour drift, a softer glow), plus teammate footprint colours | Game pass per pack, or a developer product per item | Looks only. Dots are the whole picture, so this is the most visible thing a player can own | `Upgrades.cosmetics` (add a `robux` flag), `Config.Monetization.cosmeticPackProductId` |
| 3 | **Gun housings and view-model charms** | Game pass | Looks only | `Upgrades.cosmetics` slot `gun` |
| 4 | **Surveyor's Kit**: a mid-level checkpoint beacon | Game pass | Saves a long walk back, gives no information about the dark. Already wired, prompted only after 2 cleared levels | `Config.Monetization.surveyorKitPassId` |
| 5 | **Private servers** | Roblox built-in | Friend groups who play together come back together | Enable in the place settings |
| 6 | **Survey Log**: a season track of cosmetic rewards for playing (free track, paid track) | Game pass per season | Rewards play, not payment; the paid track is cosmetic only | Needs a new season table and a save field |

Not recommended: selling Static. It is fast to add (a developer product) but it lets people
buy the scanner upgrades, which turns the progression into pay-to-win and empties the reason to
replay. If it is ever added, cap it (one small pack a day) and never sell charges.

## Next progression ideas (not built)

- **Surveyor rank**: a level that rises with lifetime Static earned, shown on the title and to
  teammates. Each rank unlocks a cosmetic or a new bench item. Cheap to add: one save field.
- **Field log**: a collection screen of every hidden object, tape, poster and manual page found
  across runs, with blanks for the missing ones. The story already has 180 entries.
- **Weekly survey**: the featured anomaly (already rotated weekly in `Daily`) with a goal, such
  as "clear the Flooded Wing using two sweeps or fewer", paying a cosmetic.

## When it is time

1. Create the passes and products on the Creator Dashboard; put their ids in
   `Config.Monetization`.
2. Add `MarketplaceService.ProcessReceipt` on the server before any developer product goes live
   (game passes do not need it).
3. Keep `promptAfterLevels`: never show a purchase before a player has cleared two levels.
