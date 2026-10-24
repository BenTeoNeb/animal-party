# New Game! (working title)

*Nouveau Jeu !* in French. The next game made with children for children,
built on the same framework as [Lava Rescue!](../volcan) and reusing its
drawings. The idea is still to come.

## What is already here

Copied from `volcan/` (the two games now live their own lives):

- **Engine**: controllers and keyboard for 1 or 2 players (`input.lua`), sound
  effects and music made in code (`sfx.lua`, `synth.lua`, `musique.lua`),
  French / English (`lang.lua`), the drawings and animations (`art.lua`), the
  game log (`journal.lua`), the menu and the character select (`main.lua`).
- **Art**: all of Lava Rescue's images (`images/`): Rami, Zina and Lila with
  their animations, the animals and big mamas, trees (and burnt trees), huts
  and houses, the pond and fish, the volcano, stones and forest props. The
  style reference (`planches/reference.jpeg`) and `art.json` are kept so new
  drawings made with the `game-art` skill match the old ones.
- **Tools**: `outils/build.sh` (Mac, Windows, Linux / Bazzite, .love),
  `outils/linux/` (installer), `outils/icone/` (still draws Lava Rescue's
  icon), and the image tools.

`world.lua` is a playground for now: the kids walk in the forest among the
animals, and the bottom button says hello to the nearest one.

## Play

```bash
/Applications/love.app/Contents/MacOS/love jeu2     # macOS
love jeu2                                           # Linux / Windows
sh jeu2/outils/build.sh                             # -> dist/
```

## Once the game has a name

Rename the folder and replace the placeholders `New Game` / `NewGame` /
`new-game` / `Nouveau Jeu` / `nouveau-jeu` / `jeu2` (in `conf.lua`,
`lang.lua`, `outils/`), and make a new icon.
