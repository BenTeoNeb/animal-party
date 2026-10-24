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
- **Fonts** (`fonts/`, SIL Open Font License, see the OFL files there):
  Andika, made by SIL for children learning to read, for every text and
  number; Fredoka (a bold instance of the variable font), for the titles and
  names. Boxes and signs are wooden planks drawn in code (`art.panel`,
  `art.paper`), and numbers on things are round tags (`art.disk`) with one
  colour code: yellow to do, green right, red too many.
- **Tools**: `outils/build.sh` (Mac, Windows, Linux / Bazzite, .love),
  `outils/linux/` (installer), `outils/icone/` (draws the icon from the
  game's images), and the image tools.

## The games

The game starts on a **games screen**: big pictures in two rows, the stick
or D-pad to pick one, the bottom button to choose it. Then each kid picks Rami, Zina or
Lila (the right button goes back to the games). The level to start with is
in the menu (Start).

### Difficulty: small steps that adapt

Each game has a ladder of 6 to 8 small steps (the `STEPS` table at the top
of its file), shown as dots at the top right. After every task the game
checks whether it went well, right the first time: a few in a row (2 for the
pens, the train, the nest and the eggs, whose tasks are long; 3 for
Peekaboo and the path) and it goes up a step, with a sparkle; two not right
in a row and it quietly goes down one. Each kid's step in each game is
saved (`progres.lua` in the save folder), and the next game starts one step
below it; the level in the menu is the lowest step to start from (1, a third
or two thirds of the ladder). The levels below are where the ladders go.

### The pens

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

Animals wearing a number wait in the meadow: call them **in
order** and lead them onto the platform (behind the train, with its two
lamp posts), where each one climbs into its numbered wagon and says its
number. The engine and the four wagon colours are drawings (game-art). Only the next number follows you;
another one shakes its head. A board at the top shows the train's numbers
(yellow: following, green: in the train, the next one pulses); after 10
seconds without finding it, the next animal sparkles. When everyone is in,
the train whistles and leaves.

- **Level 1**: 1 to 3, 4 or 5.
- **Level 2**: five numbers starting from 2 to 5 (4 5 6 7 8), with a number
  just before and just after that are not in the train.
- **Level 3**: count down to 1 (from 5 to 8), with bigger numbers as decoys.

### Peekaboo! (Coucou !)

Animals hop out of their hiding places (a berry bush, a flowery bush, a
hollow log), in dice patterns, for a moment, then hide again: how many were
there? Stand on the stepping stone with that number. Right: they come out
again and are counted together, one by one, then the sum shows ("2 + 3 = 5").
Not right: the stone wobbles and darkens, and they peek out again. After
answering, the kid walks back to the start by itself. 5 right answers make a
round. It trains seeing small numbers at a glance, then adding groups.

- **Level 1**: one hiding place, 1 to 4 animals, 3 stones.
- **Level 2**: two hiding places, 1 to 3 animals each, 3 stones.
- **Level 3**: three hiding places, 1 to 3 animals each, 4 stones.

### The Number Path (Le chemin)

Stones numbered 0 to 10 wind across the meadow. An animal sits on one, and
the sign at the top says where it goes: "2 + 3 = ?" ("-" means going back).
The kid answers in their head, by standing on the stone of the result:
right, the animal hops there stone by stone, saying the numbers and filling
one dot per hop under the 3 (the proof on the number line), and its friend
pops out by that stone; not right, the stone wobbles and darkens, and the
animal sparkles: now the bottom button next to it makes it hop one stone
(the right button hops back), to count it out. After answering the kid walks
back by itself. 5 trips make a round.

- **Level 1**: adding 1 to 3, up to 8.
- **Level 2**: taking away 1 to 3.
- **Level 3**: both, up to 5 hops, from 0 to 10.

### The Nest of 10 (Le nid de 10)

In the middle of the meadow, a hen house shaped like a ten-frame (2 rows of
5 straw nests), some nests already with a hen: bring the missing hens. Each
one sits in an empty nest and is counted on from the ones already there
("7, 8, 9, 10"); full, a golden egg appears. The bonds of 10, the base of
the work on tens (the Singapore method's ten-frame). 5 nests make a round.

- **Level 1**: bring them as you like; one too many is refused.
- **Level 2**: bring exactly the missing number, all at once (count the
  empty nests first).
- **Level 3**: the nest has a straw roof and the sign says "7 + ? = 10"; not
  right, the roof lifts a moment to show the nest.

### The Egg Boxes (Les œufs)

Eggs lie all over the meadow: walk on them to pick them up; 10 eggs snap
into a box ("clac!"). The market cart asks for a number, say 34: bring it
exactly 3 boxes and 4 eggs. It counts them, "10, 20, 30, 31… 34", and
shows "34 = 30 + 4". Too many or too few, it wobbles; the right button puts
an egg down, and with no loose egg it opens a box (one egg down, 9 loose:
breaking a ten). What a kid carries shows above their head, in boxes and
eggs. Tens and ones to 100 (the Singapore method's bundles of ten).
3 deliveries make a round.

Full boxes lie about at every level (one or two more than needed): walk on
one to pick it up. Loose eggs too, to fill a box yourself.

- **Level 1**: 10 to 19; the sign shows the number and the same in boxes
  and eggs.
- **Level 2**: 20 to 59, with the pictures.
- **Level 3**: 20 to 99, the number only (the pictures come back after a
  wrong try).

The games share the meadow, the kids and the animals (`world.lua`, which is
also the pens game); the train and Peekaboo add their own rules
(`train.lua`, `flash.lua`, `path.lua`, `nid.lua`, `oeufs.lua`) through the hooks listed at the top of
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
