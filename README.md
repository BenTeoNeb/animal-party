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

Three pens stand around the meadow, each with a small sign: a number and an
animal ("3 foxes"). Bring exactly that many of that animal into the pen. The
animals go in one at a time, with a note going up the scale and the number
popping up next to the sign, so the kids can count out loud. The sign turns
green with a star when the pen is right; its number turns red when there are
too many. Another animal shakes its head and stays in line.

The meadow has three biomes, in a different place each game: a pine wood
(squirrels and foxes), an orchard (hens and sheep) and an oak wood with a
pond (piglets, hedgehogs and does). Each animal lives in its biome, and goes back there
when it's let go somewhere else. Trees turn see-through when someone is
behind them.

- **Level 1, count**: the pens are empty, bring 1 to 5.
- **Level 2, add**: some animals are already inside, bring the missing ones.
- **Level 3, take away**: some pens have too many: take the extra ones out
  (bottom button inside the pen), then let them go outside (right button).

Brought the wrong animals? The right button (B, or Enter / G on the
keyboard) lets go of the last one in line; hold it to let go of all of them.

No timer, no losing. When all three pens are right: a party and a star,
then the next round. After 3 rounds, the next level. The level to start
with is chosen in the menu (Start) on the home screen.

### The Animal Train

The second game (the game is chosen on the home screen, top right, with
up / down, or in the menu). Animals wearing a number wait in the meadow: call them **in
order** and lead them onto the platform, where each one climbs into its
numbered wagon and says its number. Only the next number follows you;
another one shakes its head. A board at the top shows the train's numbers
(yellow: following, green: in the train, the next one pulses); after 10
seconds without finding it, the next animal sparkles. When everyone is in,
the train whistles and leaves.

- **Level 1**: 1 to 3, 4 or 5.
- **Level 2**: five numbers starting from 2 to 5 (4 5 6 7 8), with a number
  just before and just after that are not in the train.
- **Level 3**: count down to 1 (from 5 to 8), with bigger numbers as decoys.

### Peekaboo! (Coucou !)

The third game. A few animals hop out of the big bush in the middle, in a
dice pattern, for a moment, then hide again: how many were there? Stand on
the stone with that number. Right: they come out again and are counted
together, one by one. Not right: the stone wobbles and greys, and they peek
out again. 5 right answers make a round (the stars at the top). It trains
seeing a small number at a glance, without counting one by one.

- **Level 1**: 1 to 3 animals, out 3 seconds, 3 stones.
- **Level 2**: 2 to 5 animals, 2.5 seconds, 3 stones.
- **Level 3**: 3 to 6 animals, 2 seconds, 4 stones.

The games share the meadow, the kids and the animals (`world.lua`, which is
also the pens game); the train and Peekaboo add their own rules
(`train.lua`, `flash.lua`) through the hooks listed at the top of
`world.lua`.

**The kids' voices**: record them saying the numbers and put the files in
`voix/fr/1.ogg`, `voix/fr/2.ogg`... (`voix/en/` in English; .ogg, .mp3 or
.wav). The game says the numbers with their voices instead of the notes.

## Play

```bash
/Applications/love.app/Contents/MacOS/love fete     # macOS
love fete                                           # Linux / Windows
sh fete/outils/build.sh                             # -> dist/AnimalParty-*
```
