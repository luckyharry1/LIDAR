# Voice, radio and sound (v2)

Vasco: the radio was vague, unclear and only text. In v2 every spoken line is voiced and subtitled, and the radio is a system with rules the player can learn.

## Who speaks and how

Casting notes are in `lore-text.json` under `voices` (also `LoreText.voices`). Short form:

| Voice | Direction |
|---|---|
| Theo | late 20s to early 30s, tired, dry humour that cracks under pressure; talks to himself, never to camera |
| Ines (Base) | 50s to 60s, calm, low, unhurried; teacher voice; radio filter on Base lines |
| Joss | 40s, warm, fast, jokes to cover nerves |
| Hana | 30s, flat, practical, short sentences |
| Lena | 30s, generous, sounds like she just laughed |
| Ravi | 20s, whispery, jumpy |
| Pim | late teens or 20, bright, too hopeful |
| Hollis / Tobi / Quill | tape voices that get quieter and flatter across their tapes |
| Pike | 1994, cheerful engineer's voice that stays cheerful through the worst thing |
| Announcer | 1994 promo voice, smooth, bright, slightly too slow |
| Echo | a copy of Ravi but missing the pauses; speaks half a beat early |
| Base? (fake radio) | Ines's voice with no static and no questions, only commands |

Roblox has no built-in text-to-speech for in-experience audio, so voice has to be uploaded audio. Options: record the lines (Vasco, friends, or a hired voice actor), or generate them with an offline TTS tool and upload the audio. All lines are written to be short so a full pass is about 25 minutes of speech. Subtitles are required either way (and are the fallback while audio is missing). Asset ids go in `docs/ASSETS.md`.

## Radio rules (the system)

- **Real Base is Ines.** She says "Base to Theo". She **asks what you see** and **gives plain guidance** (where the next surveyor is, what the hazard is). She **never says "come to me"**.
- **Fake Base is the Echo.** It uses the same handset. It **only commands** and always says "come to me". It speaks half a beat early with no static artefact (the tell). Plays only on Level 2 near the Echo (`radio.fake.*`).
- **Triggers:** level start (`radio.l0` to `radio.l4`), idle in the dark (`radio.idle.*`, rarely), a surveyor nearby but unseen (`radio.surveyor.near`), after a level clear (`radio.clear`), respawn (`radio.back.*`).
- **Mix:** radio filter (narrow band, light static bed), ducks the music, comes out of the handset on the HUD with a small waveform so it reads as a voice, not UI. Subtitles with speaker name.
- **Radio comes alive** at Outpost Zero (the Night Desk) after tier 2. Before that, Theo has only himself and the tape.

## Theo's thoughts

`thought.*` lines are Theo's spoken reactions: subtitled and voiced, triggered by events (first dot, first lamp wake, first Pacer, first death, entering the Falls). Their job is to say what the player is thinking, so the story reaches the player directly. Cap the rate: no more than one thought per ~20 seconds, never over a scare.

## Cutscenes and tapes

See `04-cutscenes-and-tapes.md`. Every tape plays on an in-world screen (CRT, projector, monitor, camcorder). The player can walk away; the audio continues quietly and ducks the world. The screen glows in the area's colour as it plays, painting the nearby wall and floor in that area's backdrop.

## Sound cues per area (for the audio pass)

| Area | Ambience | Scare cue before the monster |
|---|---|---|
| Level 0 | fluorescent buzz that cuts out as you enter, fan, far copier | keys stop, a drawer closes |
| Level 1 | long-reverb drips, pump thud | the water goes silent, one splash |
| Falls | waterfall, chimes, impossible birds, one string guitar | none (Refuge). One far note of the dark, rarely |
| Level 2 | PA hiss, squeaking wheels, call bell | Ravi's voice on the radio, a half-beat early |
| Level 3 | stone drips, glowcap pulse, glass chimes | a shutter click behind you |
| Level 4 | ramp wind, tyre squeal, the Lamp's hum far below (the beacon) | every ambience drops at once |
| Lamp Room | the Lamp's hum, kettle, wind in the shaft | none |
