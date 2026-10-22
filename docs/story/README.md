# LIDAR story and lore (v2, Backrooms pivot)

Status 2026-10-22: v2 written. v1 ("The Understory") is kept in `v1/`.

| File | For |
|---|---|
| `01-story-bible.md` | The pivot, setting, cast, truth, journey, tone |
| `02-sections.md` | Route, what each light shows (looks), each Level and camp, pacing, gates |
| `03-ingame-text.md` | Every line with id and placement (generated) |
| `04-cutscenes-and-tapes.md` | Opening cutscene, 7 videotapes, 6 surveyor dialogues, 2 endings (generated) |
| `05-voice-and-radio.md` | Casting, radio rules, sound cues |
| `LoreText.luau` | Drop-in module: `get`, `ofKind`, `scene`, `look`; plus `scenes`, `looks`, `voices` |
| `lore-text.json` | Same data as JSON |
| `build_text.py` | Source of truth. Edit it and run `python3 build_text.py` |

## In the game (22 Oct, PR luckyharry1/LIDAR#12)

Cards, recorders, manual rules, radio, camp notes, hidden objects, the finale and the end cards
now read the v2 ids; only lamp-bag tags and a few signs and items still use v1 text. The opening
cutscene, the orientation tape, Theo's subtitled thoughts, surveyor scenes at the camps and
the HUD goal are live. Unused so far: tapes 2 to 7 (no screens placed yet), POIs with no prop
(copier, ticket machine, Pike's table, rope bridge, doorframe), the journal, voice audio.

## For the build thread

- `LoreText.luau` keeps the v1 API (`get`, `ofKind`) and adds `scene(id)` and `look(key)`.
- **v1 ids are still present, marked `legacy = true`**, so the running build keeps compiling. Migrate callers to v2 ids, then delete the legacy block by removing `load_legacy()` in the script.
- Id map (v1 -> v2):
  - `card.annex/desk/flood/falls/over/bunk/found/lamp` -> `card.l0/desk/l1/falls/l2/dorm/l4/lamp`; `card.haven.*` -> `card.c0/c1/c2/c3`
  - `rec.annex.*` -> `rec.l0.*`; `rec.flood.*` -> `rec.l1.*`; `rec.over.*` -> `rec.l2.*`/`rec.l3.*`; `rec.found.*` -> `rec.l3.2/3`, `rec.l4.1`
  - `rev.*` and `sign.*` objects -> `poi.*` (each has a Theo `thought` and a `look`); `rev.nook.*` stay as lamp-bag text
  - `ent.wanderer/listener/mimic/stalker` keep their ids with new text
  - `rule.01`..`rule.12` rewritten plainly
  - `radio.base.*`, `radio.fake.*`, `radio.back.*` -> `radio.*` (voiced; same role)
  - `npc.ines.*` -> scene `npc.ines`; new scenes `npc.joss/hana/lena/ravi/pim`
  - `end.up` / `end.stay` are now scenes (cutscenes); `choice.up/stay` unchanged
- New kinds to wire up: `goal` (HUD), `journal` (notebook), `thought` (voiced reaction), `plaque` (Survey Bulletin), `poi`.
- New data: `looks` per area (wall, floor, light, sound) for lamp/POI ignition patches, and `voices` for casting.
- Light sensitivity: lamps, POIs and tape screens should ignite on the first dot or any dot within ~6 to 10 studs; see `02-sections.md`.

Open for later: more tapes (2 slots), Relay Levels (school, mall, pool, station), sound cues to asset ids, `thought` rate limiting.
