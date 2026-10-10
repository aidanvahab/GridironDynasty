# Third-Party Software and Assets

| Item | Source | License | Use |
|---|---|---|---|
| Godot Engine 4.7.2 (runtime + export templates) | godotengine.org | MIT | Game engine |
| Barlow (Regular, SemiBold, Bold) | Google Fonts / Jeremy Tribby | SIL Open Font License 1.1 (`assets/fonts/OFL-Barlow.txt`) | UI body text |
| Barlow Condensed (SemiBold, Bold, ExtraBold, Black Italic) | Google Fonts / Jeremy Tribby | SIL Open Font License 1.1 (`assets/fonts/OFL-BarlowCondensed.txt`) | Headings, scoreboard, jersey numbers |

Everything else is original to this project:

* **Audio** — all sound effects, crowd ambience and music are synthesized from
  scratch by `tools/generate_audio.py` (numpy + ffmpeg). No samples are used.
* **3D art** — players, stadiums, crowd, field, goalposts, trophy and props are
  built procedurally at runtime from engine primitives and generated meshes.
* **2D art** — team logos, player portraits, play diagrams and icons are drawn
  procedurally (`scripts/ui/widgets`). The app icon is an original SVG.
* **Teams, players, league and names** — fictional and generated. Any
  resemblance to real teams or people is coincidental. The game is not
  affiliated with any real league.
