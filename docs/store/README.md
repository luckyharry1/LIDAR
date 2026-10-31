# Store art

Icon and thumbnails for the Roblox experience page. Generated, not captured: see
`scripts/art/store_art.py` and `docs/ASSETS.md`.

| File | Use |
| --- | --- |
| `icon-512.png`, `icon-1024.png` | The icon (a copy of option A). Roblox takes 512x512; the 1024 copy is for sharper previews |
| `icon-a-corridor-*`, `icon-b-radar-*`, `icon-c-letter-*` | Three icon options: A a dotted corridor with something red looming in it (recommended, it shows the whole game at 150x150), B a radar-style scan burst with a red and a green blip, C a dot-matrix L with a red last dot |
| `thumbnail-1-hero.png` | First thumbnail, the one shown in search: "The dark is full. Your scanner is all you have." |
| `thumbnail-2-scan.png` | "You are not alone": a scanned room with red presences in the dark around it |
| `thumbnail-3-aura.png` | "Listen.": red screen edges and a heartbeat |
| `thumbnail-4-together.png` | "Scan together": friends' green scans over blue water |
| `thumbnail-5-camp.png` | A lit surveyor camp |
| `thumbnail-6-lore.png` | "The dark has a story": half-scanned survey bulletins and a tape marker, lines taken from the game's own text |
| `thumbnail-7-looks.png` | "Make the dark yours": the scanner skins from `Skins.luau` (PR #15: Classic, four earned by playtime, three Robux) |

Thumbnails are 1920x1080. Upload them in this order in Creator Hub > Experience > Media.
Replace any of them with a real Studio capture (HUD hidden) when there is one. The looks
panel mirrors `src/shared/data/Skins.luau` (names, wall colours, playtime minutes); if skins
change, edit `LOOKS_EARNED` and `LOOKS_ROBUX` in the script and re-render.
