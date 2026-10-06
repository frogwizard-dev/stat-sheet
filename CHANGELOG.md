# StatSheet

## 0.3.5

### Under the hood
- Values the game hides from add-ons are checked for first everywhere (the stat audit's shapeshift form, unreadable stats), with FrogLib's checks shared with the other Frog Wizard add-ons.
- The tab row's class colour is FrogLib's: a class colour add-on's colour is used if you have one.

## 0.3.4

### Under the hood
- Shares its options page and its texture and font lists with the other Frog Wizard add-ons (one copy of the code, so a fix reaches them all at once). Nothing changes in how it looks or works.

## 0.3.3

### Options
- Listed with the rest of Frog Wizard's add-ons: under a "Frog Wizard" heading in the AddOn list, and in its own "Frog Wizard" section of Options > AddOns, whose page lists them all with a button to each one's settings.

## 0.3.2

### Changes
- On the Overview, your attributes and what they give you (crit, attack power, health, mana, regen) now come before "What +10 of each gets you".
- On the Offense tab, your stats (Melee, Ranged, Spells) now come before the breakdowns: "Where your damage comes from" and "Where your swings go" as melee, "Where your spells go" and "Casts from full mana" as a caster.

## 0.3.1

### New
- **More room**: the character window and its stats pane are 110 wider, so nothing is cut short. Adjust it with Extra width in the settings (0 puts the window back to its normal size).
- **Melee or Caster changes the Offense tab.** As a caster it shows spell power, spell crit and mana regen; where your spells go (hits, crits, resisted) against your level and a raid boss; and how many casts a full mana bar gives for each of your spells. The Overview's first tile follows the switch too. The switch now also sits at the top of the Offense tab.

### Changes
- "Since you logged in" is a card per change, much easier to read: the item's icon and name in its quality colour, how long ago, what it replaced, the stats that moved, and what they add up to (real DPS, effective health). Skill-ups say what they improved.
- Legend labels under the bars size their columns to fit, so they no longer run into each other.

## 0.3.0

A redesign: four tabs, numbers that tell you something, and the look of whichever character sheet you use.

### New
- **Tabs**: Overview, Offense, Defense and Gear, instead of one long list. The tab you were on is remembered.
- **Real DPS**: what your auto-attacks really do after misses, dodges, glancing blows and crits, next to the paper DPS the game shows.
- **What +10 of each gets you**: how much +10 Strength, Agility, Stamina, Intellect or Spirit would add for you right now (DPS, effective health, mana, regen), with a melee / caster switch.
- **Where your swings go**: a split bar of hits, glancing blows, crits, misses and dodges, against an enemy of your level and a raid boss.
- **When you're swung at**: the same for attacks against you, including crits and crushing blows.
- **Caps**: weapon skill, defense and hit, each with a bar and what being short costs.
- **Since you logged in**: gear swaps, skill-ups and level-ups, with what each changed (including real DPS and effective health).
- **Item tooltips** show what wearing that item instead of yours would change: real DPS, effective health, spell power, mana and regen. Can be turned off in the settings.
- Gear tab: item level, durability, your weapon's own DPS, and what your items add up to.
- The EllesmereUI look uses Expressway; the Forever look uses the game's own fonts (Friz Quadrata, with Arial Narrow for the small print).

### Changes
- The Insights section is gone: its numbers now live in the tiles and bars.

## 0.2.0

### New
- A new look. Four headline numbers on top (health, mana, DPS and how much armor takes off; spell damage instead of DPS for mages, priests and warlocks), thin bars for weapon skill, defense and durability, and details beside each stat's name, or underneath when they don't fit.
- The panel matches the character sheet it's on: EllesmereUI's dark skin (coloured headers between thin lines), or Blizzard's own Forever look (its bronze header bars, shaded rows, gold names and white values). It follows the sheet by itself, or you can pick one in the settings.
- Click a section's header to fold it away; it stays folded.
- General now has your average item level, durability (with your most worn item) and what your equipped items add up to.
- Attributes show what they give, worked out exactly as Forever's own character sheet does: attack power and block value from Strength; crit, attack power, dodge and armor from Agility; health from Stamina; mana and spell crit from Intellect; health and mana regen from Spirit. Turn it off in the settings to go back to two stats to a row.
- Weapon skill, named for your weapon (for example "Two-Handed Maces 40/45", in yellow below the cap), with what being short of the cap costs. Its tooltip shows your hit and crit against your own level and raid bosses, and how often your hits glance on a boss.
- Defense skill, with the chance enemies of each level miss, crit and land crushing blows on you.
- Energy regen while you're in cat form.
- New Insights section: effective health against physical damage, your chance to miss with melee and spells and to be dodged (for enemies up to 3 levels higher, in the tooltips), your chance to avoid melee attacks or be critically hit, and how long your mana takes to fill from empty.
- Mana regen is measured as you play. A tick by Mana Regen means the game's number checked out; if the measurement disagrees, it shows what was measured.
- Armor's tooltip shows the damage it takes off against enemies up to 3 levels above you.
- `/statsheet audit` saves the stats the game reports, for checking the panel's numbers.

### Changes
- Every rule now comes from Forever's own interface code, so the panel agrees with the game's sheet: armor reduction, miss, dodge, glancing and crushing chances, and weapon and defense skill.
- Grey details (what a stat gives, what armor takes off) move to a line of their own when they don't fit beside the value, instead of running over the stat's name.
- Mana regen shows a decimal (37.5 rather than 38); the game's sheet rounds it down to 37.
- The weapon tooltip explains why the game's own sheet can show a slightly lower DPS (it rounds the damage first).

## 0.1.0

First version.

- Replaces the character sheet's stats list with one compact panel that shows every stat at once, two to a row, with no scrolling.
- Weapons show their damage, swing speed and DPS on one line (main hand, off hand, and ranged or wand), with no need to hover.
- Attack power shows how much DPS it adds; mana regen shows both the out-of-casting and while-casting rates.
- Spell damage, healing, crit and hit; dodge, parry, block, armor (with the damage it takes off) and resistances.
- Buffed stats show in green and lowered ones in red. Hover any stat for the breakdown (per-school spell power and crit, base and bonus, and so on).
- Matches EllesmereUI's character sheet colours and font when it's installed.
- Settings (`/statsheet`): put the panel beside the window instead of over the list, font, text size, row spacing, hide zero stats, and which sections show.
