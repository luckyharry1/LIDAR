# Publishing

The owner's checklist for putting LIDAR on Roblox. Nothing here has been done yet: the game
has never been published. Items marked *(your call)* are decisions the code does not make.

## 0. Release readiness (31 Oct)

What is ready, what is not, in the order to do it.

**Ready**
- `scripts/check.sh` passes on the integration branch (stylua, selene, 76+ Lune tests, a Rojo
  build). `build/LIDAR.rbxl` is the file to open in Studio and publish.
- Studio playtest (one player, PC): title, the 3D opening and SKIP, intake, tiers, hidden
  objects, pits, plates, havens, the stairwell with its GO DOWN prompt, the level-cleared
  card, the weaker scanner and the bench. See the dated sections of `docs/PROGRESS.md`.
- Place settings that the project file already sets: `CharacterAutoLoads` off,
  `StreamingEnabled` off, black lighting.

**Not ready (needs a person, or a published place)**
1. Two players, real DataStore saves, the daily board with several entries, phone and gamepad
   hardware, and sound by ear. Only a published or multi-client test can show these.
2. Experience page: name, description, icon, thumbnails, maturity questionnaire (the art and
   page threads own the content; the form is yours to fill in).
3. Monetisation ids in `Config.Monetization` stay 0 until the passes and products exist in
   the Creator Hub (`docs/MONETIZATION.md`). With 0 the game simply sells nothing.
4. The three `ContentId rbxassetid://203785492 ... Asset type does not match` lines in the
   Studio output come from an asset id that is not in this repo (probably a default avatar
   asset). Worth a look in the Output window with the Creator Hub open.

**Publishing steps** (nothing here has been done; it needs your Roblox account)
1. `bash scripts/check.sh`, then open `build/LIDAR.rbxl` in Studio.
2. Turn on Game Settings > Security > Allow API Services, and set max players to 4.
3. File > Publish to Roblox as a new experience (or an existing place id of your own).
4. Play the published place once alone and once with a friend, using section 8.

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
| Name, description | *(your call)* | See the page brief in the project files (`roblox-page/page-copy.md`). |
| Icon and thumbnails | Upload `docs/store/icon-512.png` and `docs/store/thumbnail-1` to `7` in that order (1 is the one search shows) | Creator Hub > Experience > Media. Generated stand-ins from `scripts/art/store_art.py`; replace with real Studio captures when you have them. |

## 4. Data stores

| Store | Kind | Holds |
| --- | --- | --- |
| `LidarSave` (`Config.Save.storeName`) | Standard | One profile per player (Static, upgrades, cosmetics, settings, checkpoint, story progress, stats), with a session lock so two servers cannot write the same profile. Saves use `UpdateAsync`. |
| `LidarDaily_YYYYMMDD` (`Config.Daily.storePrefix` + date) | Ordered | One per day: each player's best time on the daily run. |

Changing `Config.Save.storeName` starts everyone from scratch. Bump `Config.SaveVersion` and
add a migration in `src/shared/pure/SaveData.luau` instead when the profile shape changes.

## 5. Optional: monetisation

All off while the ids are zero; the game runs fine without them. A zero id shows "coming soon"
on the skins screen and hides the Surveyor's Kit button. For each pass below: Creator Hub >
the experience > Monetization > Passes > Create a pass, then paste the number from its URL into
`src/shared/Config.luau` under `Config.Monetization` and publish again. The buy buttons read the
price from the pass, so set it there.

| Config key | Pass to create | Suggested name and price | What it does |
| --- | --- | --- | --- |
| `surveyorKitPassId` | Surveyor's Kit | "Surveyor's Kit", 99 Robux | A checkpoint beacon placed in each level for owners. The workbench shows a purchase button, but never before the player has cleared `promptAfterLevels` (2) levels. |
| `skinPassIds.rose` | Rose Quartz skin | "Rose Quartz Scanner", 75 Robux | Pink dots and a rose-gold gun |
| `skinPassIds.chrome` | Chrome skin | "Chrome Scanner", 75 Robux | Bright white dots and a mirror gun |
| `skinPassIds.nightbloom` | Nightbloom skin | "Nightbloom Scanner", 75 Robux | Deep violet dots and a midnight gun |
| `skinPassIds.pack` | Phosphor Pack | "Phosphor Pack: every skin", 199 Robux | Unlocks every Robux skin, including ones added later (your call whether to promise that on the pass page) |

The pass icon can be a screenshot of the title corridor in that skin: equip the skin, press the
SKINS button from the title and take the picture from there (the dots on the title scene wear
the skin). Prices are suggestions; the code never assumes them.

Playtime skins (Tungsten, Glacier, Orchid, Blueprint) need nothing created. Developer products
and the `ProcessReceipt` handler are not used yet; the brainstorm in `docs/MONETIZATION.md`
lists what would need them.

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
