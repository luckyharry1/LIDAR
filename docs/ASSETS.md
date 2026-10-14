# Assets

Every asset the game uses and where it comes from. There are no uploaded images, meshes,
models or animations: everything in the world is built from primitive parts in code, and
almost all of it is invisible (the dots are the picture). What remains is sound, two fonts
and one particle texture.

All sound ids live in `Config.Audio` (`src/shared/Config.luau`); set any of them to `""` to
silence it. Every sound, including the ones the server makes, plays through one sound group,
so the volume setting covers all of it.

## Built into the Roblox client

These ship inside every Roblox client (`rbxasset://`), so they always load and need no
permission.

| Config key | Asset | Used for |
| --- | --- | --- |
| `tick` | `rbxasset://sounds/volume_slider.ogg` | Scan ticks (pitched by distance), the sweep's falling run of ticks, interface clicks, the radio's crackle, the recorder click |
| `thud` | `rbxasset://sounds/action_jump_land.mp3` | Stranded surveyors tapping on the wall, the landing after a fall |
| `air` | `rbxasset://sounds/action_falling.ogg` | The sweep's rush, falling into a pit, the low hum of humming props in levels (server) |
| `wade` | `rbxasset://sounds/action_swim.mp3` | Wading through flooded cells |
| `rumble` | `rbxasset://sounds/impact_explosion_03.mp3` | Being caught (under the roar), the sting when a monster first arrives close |
| `ping` | `rbxasset://sounds/electronicpingshort.wav` | Alarm plates (the crew's bell), the Pulse Radar |
| (font) | Roboto Mono (`Enum.Font.RobotoMono`, `rbxasset://fonts/families/RobotoMono.json`) | All interface text |
| (font) | Merriweather (`Enum.Font.Merriweather`, `rbxasset://fonts/families/Merriweather.json`) | Notes and pages on paper |
| (texture) | `rbxasset://textures/particles/smoke_main.dds` | Mist round the waterfall at the Falls (`src/server/LoreRooms.luau`) |

## From Roblox's audio library

These are `rbxassetid://` sounds. The comment in `Config.Audio` records them as coming from
Roblox's licensed libraries (Pro Sound Effects and APM), which Roblox makes free to use in
experiences. The ids and descriptions below are as recorded there; the library source of each
id has not been re-checked since. Before publishing, open each one in the Creator Store to
confirm it is still public and allowed in your experience (see `docs/PUBLISHING.md`).

| Config key | Asset id | Description (from `Config.Audio`) | Used for |
| --- | --- | --- | --- |
| `ambience` | 9125970426 | Low engine-room rumble with sporadic distant noises | Room tone under everything in the dark |
| `drips` | 9112773041 | Water drips, creaks and distant metal | Second layer of room tone |
| `presence` | 9113586520 | Slow airy breathing | Rises as a monster gets close |
| `heartbeat` | 9043365842 | Heartbeat | Loops faster and louder as a monster gets close |
| `bumps` | 9113136235 | Far-off bumps and creaks | Played now and then from a random direction |
| `wandererVoice` | 9112863181 | Rumbling breath | The Pacer (Wanderer); also the Echo (Mimic) once revealed, pitched up |
| `wandererStep` | 9114166413 | One heavy footstep | Every monster footprint, pitched per kind |
| `listenerVoice` | 9119531802 | Ratchety clicks | The Hush (Listener) |
| `stalkerVoice` | 9126147232 | Bending metal whine | The Still (Stalker), only while it moves |
| `caughtRoar` | 9113980319 | Roar | Being caught |
| `door` | 9114434781 | Door | The exit opening |
| `waterfall` | 9120552550 | Waterfall | The Falls (lit room), made by the server |

## Story text

All written story is original, by the story thread, in `docs/story/` (see `docs/LORE.md`).
It names no real people, places or brands.
