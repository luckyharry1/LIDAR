# Monetization plan

The skin system and the Surveyor's Kit are built; no real purchase exists until their ids are
filled in (they live in `Config.Monetization`; zero means "not configured" and the button reads
"coming soon"). The rest is the plan for when the game has players. The list of passes to create
is in `docs/PUBLISHING.md` section 5.

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
- **Scanner skins** (`data/Skins`, the SKINS button on the start screen and at the workbench):
  four earned by time in the dark (15, 45, 90 and 180 minutes of walking; standing still or
  idling at the title earns nothing) and three that Robux buys. See "Skins" below.
- **Daily**: one shared seed a day with a leaderboard, and a visit streak.
- **Story**: hidden objects, tapes, manual pages, two endings, the endless Relay.

## What could be sold, in order of value and safety

| # | What | Type | Why it is safe | Hook in code |
| --- | --- | --- | --- | --- |
| 1 | **Premium Payouts** | Roblox pays by Premium players' play time | Costs players nothing. Every retention system above feeds it | None needed |
| 2 | **Scanner skins** (built): a colour for the dots and the gun. Three on sale, plus the Phosphor Pack for all of them | Game pass per skin, plus a pack pass | Looks only. Dots are the whole picture, so this is the most visible thing a player can own | `data/Skins`, `Config.Monetization.skinPassIds` |
| 3 | **Gun housings and view-model charms** | Game pass | Looks only | `Upgrades.cosmetics` slot `gun` |
| 4 | **Surveyor's Kit**: a mid-level checkpoint beacon | Game pass | Saves a long walk back, gives no information about the dark. Already wired, prompted only after 2 cleared levels | `Config.Monetization.surveyorKitPassId` |
| 5 | **Private servers** | Roblox built-in | Friend groups who play together come back together | Enable in the place settings |
| 6 | **Survey Log**: a season track of cosmetic rewards for playing (free track, paid track) | Game pass per season | Rewards play, not payment; the paid track is cosmetic only | Needs a new season table and a save field |

Not recommended: selling Static. It is fast to add (a developer product) but it lets people
buy the scanner upgrades, which turns the progression into pay-to-win and empties the reason to
replay. If it is ever added, cap it (one small pack a day) and never sell charges.

## Skins

A skin recolours the white terrain dots and the gun housing. It never changes range, rate,
charges or what anything does, and it keeps clear of the meaning colours (green friends, red
monsters, gold objectives, bright purple hazards), so a skinned player reads the dark the same
as everyone else.

| Skin | How you get it | Dots / gun |
| --- | --- | --- |
| Standard scanner | Always | cool white (196, 200, 210) / graphite |
| Tungsten | 15 min in the dark | muted warm / dim brass |
| Glacier | 45 min | pale mint-teal (150, 214, 196) / slate |
| Orchid | 90 min | muted lilac / plum |
| Blueprint | 180 min | bold blue (92, 140, 245) / gold, the fanciest earned skin |
| Rose Quartz | Game pass | hot pink (255, 80, 170) / bright pink |
| Aurora | Game pass | electric cyan (40, 225, 255) / glowing teal |
| Nightbloom | Game pass | bright indigo (105, 70, 255) / glowing indigo |

The earned skins are deliberately quiet, a faint tint close to the standard dots, and the
Robux skins are fully saturated so they are obvious at a glance, to you and to teammates.

- **Teammates see your skin.** Each player's terrain dot colour (`SkinRules.wallTint`: skin, else
  Static dot tint) rides along in the lobby list the server already sends, and a teammate's relayed
  scans are drawn in that colour (`Lidar.stepTeammates`, `Dots.add` tint). Only plain terrain wears
  a skin: friends stay green, monsters red, objectives gold and hazards purple, so a look can never
  be mistaken for one of those. A player with no skin shows in the standard colour, so a skinned
  and a plain player can be told apart at a glance. The gun housing is not shown to others yet.
- **Playtime** is `profile.stats.playSeconds`, counted by the server once a second while a player
  is past the title and has walked within the last minute (`Config.Monetization.playSecondsMoving`).
  The client sees it a minute at a time, and a toast announces each unlock.
- **Robux** skins are one game pass each, plus the **Phosphor Pack** (`skinPassIds.pack`), which
  unlocks every Robux skin including ones added later. Game passes need no `ProcessReceipt`.
  Ownership is checked with `UserOwnsGamePassAsync` on every join (a failed lookup never takes a
  skin away), and granted live from `PromptGamePassPurchaseFinished`.
- The server decides everything: `EquipSkin` is only accepted at the title or workbench, and
  `SkinRules.equip` refuses a skin the player has not earned or bought. Equipped skins
  override the Static dot tint and housing.
- A buy button appears only after `promptAfterLevels` cleared levels, like the Surveyor's Kit,
  and shows the live Robux price read from the pass itself, so changing a price in the Creator
  Hub needs no code change.
- Suggested prices to start with: 75 Robux a skin and 199 for the pack (about 15% off three
  skins, with more to come). Your call; they are set on the pass, not in the code.
- Adding a skin is one entry in `data/Skins.luau` (and one id slot in `skinPassIds` if it is a
  Robux skin). `tests/SkinTests.luau` checks every entry.

## Other ways to earn, brainstormed

Same rule as above: looks, comfort, time with friends, and nothing that changes how scary or
fair the dark is. Roughly in the order worth doing.

**Cheap, mostly code-free**
1. **Premium Payouts.** Roblox pays by Premium players' time in the game. Costs players nothing;
   the more the retention systems work, the more it pays.
2. **Private servers.** One switch in the place settings (set a price, or leave it free). Friend
   groups that play together come back together.
3. **Badges.** Free, and good for discovery and bragging: first level, first haven, the Lamp
   Room, both endings, "found every hidden thing on a floor", a Halloween 2026 badge. A badge can
   also gate a free cosmetic.
4. **A "Founders" skin** for everyone who joined in the first weeks, granted by a badge or a
   date check. Free, makes early players feel it, never sold again.

**Cosmetics that others see (these sell best in co-op)**
5. **More skins on a rhythm** (one a month): seasonal ones (an ember skin in autumn, a frost one
   in winter) that return later, not "gone forever", which pressures younger players.
6. **Teammates see your skin** (built, see "Skins"). Next step: show the gun housing on the
   teammate's avatar, and let a skin colour the laser beam too.
7. **Footstep trails, ping markers and emote lines** in skin colours (green trails stay for
   friends), and **gun charms** on the view-model.
8. **Title-screen backdrops** and **a name colour or rank title** on the daily board and in the
   Play Together list, such as the Surveyor rank below.

**Recurring**
9. **Survey Log season pass**: a free track and a paid track of cosmetics unlocked by playing
   (levels cleared, havens reached, hidden things found). Rewards play, not payment. The
   biggest money earner in most Roblox games, and the biggest piece of work: a season table, a
   save field and a screen.
10. **A subscription** ("Survey Club", monthly, through Roblox's experience subscriptions): a
    monthly skin, a club badge, a small daily Static stipend. Keep the stipend small so it never
    outweighs the free path.
11. **Weekly survey goals** (already planned below) paying a cosmetic, to give the season track
    something to run on.

**Direct and optional**
12. **Tip jar** ("Buy the crew a lamp", 25, 100, 500 Robux developer products) that gives a
    supporter badge and a name in the Falls guest book, nothing else. Needs `ProcessReceipt`.
13. **Gifting** a skin to a friend. Roblox has no gift for passes, so it needs developer
    products and `ProcessReceipt` with the recipient picked in game. Worth it only once skins sell.
14. **A rewarded video** (Roblox's ad formats, if the experience qualifies) that gives a
    cosmetic trinket or a one-off skin trial, never Static or charges. Optional; players who
    never watch lose nothing.
15. **An avatar item** (a UGC LIDAR scanner or a headlamp) sold in the Roblox catalog if the
    developer is eligible. Brings players in rather than earning in game.

**Growth, not revenue, but it pays for itself**
16. **Group and friends hooks**: a Roblox group with a free skin for members, and the existing
    Play Together invite. A free-for-members skin is the cheapest way to keep players tied to the
    group's announcements.
17. **Sponsored experience ads** (spend, not income) once retention numbers justify them.
    Day-1 and day-7 return rates are in the analytics events listed in `docs/PUBLISHING.md`.

**Still not recommended**: selling Static, sweep charges, revives or anything that changes what
a run feels like (see above), and random loot boxes of any kind (paid random rewards are
restricted on Roblox and sour reviews).

## Next progression ideas (not built)

- **Surveyor rank**: a level that rises with lifetime Static earned, shown on the title and to
  teammates. Each rank unlocks a cosmetic or a new bench item. Cheap to add: one save field.
- **Field log**: a collection screen of every hidden object, tape, poster and manual page found
  across runs, with blanks for the missing ones. The story already has 180 entries.
- **Weekly survey**: the featured anomaly (already rotated weekly in `Daily`) with a goal, such
  as "clear the Flooded Wing using two sweeps or fewer", paying a cosmetic.

## When it is time

1. Create the passes on the Creator Dashboard (the list is in `docs/PUBLISHING.md`); put their
   ids in `Config.Monetization`.
2. Add `MarketplaceService.ProcessReceipt` on the server before any developer product goes live
   (game passes, which the skins and the Surveyor's Kit use, do not need it).
3. Keep `promptAfterLevels`: never show a purchase before a player has cleared two levels.
