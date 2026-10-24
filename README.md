# Animal Party!

*La Fête des Animaux !* in French. A counting game made with children for
children (from about 5 years old), built on the same framework as
[Lava Rescue!](../volcan) and reusing its drawings. 1 or 2 players, together.

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
  `outils/linux/` (installer), `outils/icone/` (draws the icon from the
  game's images), and the image tools.

## The game

Each of the three pens has a sign: an animal and a number. Bring exactly
that many of that animal into the pen. The sign is a ten-frame (two rows of
5 boxes): an empty box shows the animal's shadow, a box fills in as each
animal goes in, and the animals too many show in red. The animals go in one
at a time, with a note going up the scale and the number popping up, so the
kids can count out loud. Another animal shakes its head and stays in line.

- **Level 1, count**: the pens are empty, bring 1 to 5.
- **Level 2, add**: some animals are already inside, bring the missing ones.
- **Level 3, take away**: some pens have too many: take the extra ones out
  (bottom button inside the pen), then let them go outside (right button).

No timer, no losing. When all three pens are right: a party and a star,
then the next round. After 3 rounds, the next level. The level to start
with is chosen in the menu (Start) on the home screen.

**The kids' voices**: record them saying the numbers and put the files in
`voix/fr/1.ogg`, `voix/fr/2.ogg`... (`voix/en/` in English; .ogg, .mp3 or
.wav). The game says the numbers with their voices instead of the notes.

## Play

```bash
/Applications/love.app/Contents/MacOS/love fete     # macOS
love fete                                           # Linux / Windows
sh fete/outils/build.sh                             # -> dist/AnimalParty-*
```
