# Publishing

The owner's checklist for putting LIDAR on Roblox. Nothing here has been done yet: the game
has never been published. Items marked *(your call)* are decisions the code does not make.

## 1. Before you publish

- [ ] `./scripts/check.sh` passes.
- [ ] The Studio checklist in `docs/TESTING.md` has been played through, at least single
      player on PC and the phone emulator.
- [ ] Every audio id in `docs/ASSETS.md` still plays in Studio and is allowed in your
      experience (open each in the Creator Store). Set any that is not to `""` in
      `Config.Audio`; the game runs without it.

## 2. Build and publish

1. `rojo build -o build/LIDAR.rbxl`, then open `build/LIDAR.rbxl` in Roblox Studio. (Or sync
   into an open place with `rojo serve` and the Rojo plugin.)
2. File > Publish to Roblox, as a new experience.
3. The project file already sets what the game needs: `Players.CharacterAutoLoads` off,
   `Workspace.StreamingEnabled` off, and black lighting. Keep those.

## 3. Game settings in Studio or the Creator Hub

| Setting | Value | Why |
| --- | --- | --- |
| Places > max players | 4 | A run is one party of up to `Config.Coop.maxPlayers` (4). |
| Security > Enable Studio Access to API Services | On while testing | Saves and the daily board use DataStores. Without access, Studio keeps profiles in memory and tells the player. Published servers always have access. |
| Devices | Computer, phone, tablet, console *(your call)* | The input layer handles keyboard and mouse, gamepad and touch. VR is not handled. |
| Experience questionnaire (maturity) | *(your call)* | The game is a dark horror maze: invisible monsters, jump scares, being chased and caught. The story has no blood, gore or death on screen (people are "lost", never killed). The answers are yours to give. |
| Name, description, icon, thumbnails | *(your call)* | Nothing in the repo yet. |

## 4. Data stores

| Store | Kind | Holds |
| --- | --- | --- |
| `LidarSave` (`Config.Save.storeName`) | Standard | One profile per player (Static, upgrades, cosmetics, settings, checkpoint, story progress, stats), with a session lock so two servers cannot write the same profile. Saves use `UpdateAsync`. |
| `LidarDaily_YYYYMMDD` (`Config.Daily.storePrefix` + date) | Ordered | One per day: each player's best time on the daily run. |

Changing `Config.Save.storeName` starts everyone from scratch. Bump `Config.SaveVersion` and
add a migration in `src/shared/pure/SaveData.luau` instead when the profile shape changes.

## 5. Optional: monetisation

All off while the ids are zero; the game runs fine without them.

| Config | What it does |
| --- | --- |
| `Config.Monetization.surveyorKitPassId` | A game pass id for the Surveyor's Kit: a mid-level checkpoint beacon placed in each level for owners. The workbench shows a purchase button, but never before the player has cleared `promptAfterLevels` (2) levels. |
| `Config.Monetization.cosmeticPackProductId` | A placeholder. Nothing reads it yet. |

Create the pass in the Creator Hub, then put its id in `Config.luau` and publish again.

## 6. Optional: private party servers

With `Config.Places.runPlaceId` at zero the whole game runs in one place, and each server is
one party. To give friends a private instance, add a second place to the experience for runs
and put its id in `Config.Places.runPlaceId`: the start place becomes a lobby, and pressing
Play there sends everyone in it to one reserved server of the run place
(`src/server/Party.luau`). This only works in a published experience and cannot be tested in
Studio.

## 7. Analytics

`src/server/Telemetry.luau` logs to Roblox's analytics (Creator Hub > Analytics) unless
`Config.Telemetry.enabled` is false. Every call is wrapped so analytics can never break the
game.

- Onboarding funnel, in order: Joined, PressedPlay, TutorialFirstScan, TutorialComplete,
  LevelOneCleared, LoreRoomReached, LevelThreeCleared.
- Economy: Static earned (by reason) and spent (by item).
- Progression: each level started and cleared, by tier, and each catch by monster kind.
- Custom events: hidden recorders revealed, the tier a player quit at, which ending a player
  chose (EndingUp, EndingStay).

## 8. After publishing

Run the "Published experience only" checks in `docs/TESTING.md`: saving across sessions and
servers, the daily board with several players, purchases if configured, the party flow if
configured.
