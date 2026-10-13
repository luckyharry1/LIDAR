# LIDAR story and lore

Status 2026-10-13: v1 complete (167 text entries). Written by the story thread; the build thread integrates.

| File | For |
|---|---|
| `01-story-bible.md` | The story, truth, cast, tone, the indirect-writing rule, ending |
| `02-sections.md` | Each section: what it is, feel, enemy, sound, gates, scare beats, lit rooms |
| `03-ingame-text.md` | Every line, readable, with id and where it belongs |
| `LoreText.luau` | Drop-in module: `LoreText.get(id)`, `LoreText.ofKind("recorder")` |
| `lore-text.json` | Same data as JSON |
| `build_text.py` | Source of truth. Edit this, then run `python3 build_text.py` to regenerate the other three |

Placeholders: `{deaths}`, `{floor}`, `{n}`, `{party}`. All ASCII, lines at most 90 chars.

Open items for a later pass: sound cue list per scare, optional hint set for a skipped tutorial, more Relay posters.
