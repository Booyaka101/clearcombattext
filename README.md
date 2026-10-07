# ClearCombatText

Scrolling combat text that stays readable under the secret-value API.

The Midnight and Forever clients restrict the combat log, which is why the classic
battle text addons either died or misattribute damage to whoever happened to be
standing nearby. Blizzard's answer is `C_CombatText`: you point it at one unit and
it hands you that unit's combat text events, already attributed. ClearCombatText
builds on that sanctioned API and nothing else — it never reads the combat log and
never works around a restriction. It renders what the client provides, the way
Mik's Scrolling Battle Text used to make readable:

- **Two streams.** Your damage and gains rise on the right; damage taken and
  harmful effects rise on the left. No more machine-gunned numbers over your
  character.
- **Consolidation.** Repeats of the same kind inside half a second merge into one
  line: `340 x3`, not three 340s on top of each other.
- **Crits you can see.** Criticals render larger with a pop, in their own color.
- **The usual vocabulary.** Heals, absorbs, resists, misses, honor, combo points,
  low health and low mana alerts, aura gains and fades, combat enter/leave.

## Commands

- `/cct test` — preview the styling with sample events
- `/cct anchor` — show a draggable box to position the streams, run again to lock
- `/cct` — status

Tip: turn Blizzard's own floating combat text off (Interface → Combat) or you will
see both. This addon does not touch your settings for you.

## Compatibility

Built for the WoW Forever beta (interface 16001) and Midnight retail (12.1.0 and
12.1.5). On clients without `C_CombatText` it stays inert. Every API call is
guarded: if the beta changes a signature under it, it degrades to silence rather
than erroring mid-fight.

## Honest limits

`C_CombatText` hands over the numbers, types and crits — not spell identifiers,
so per-spell icons are not currently possible the way they were before Midnight.
If that changes, icons ship.

From the author of [wow-secret-lint](https://github.com/Booyaka101/wow-secret-lint)
and [WhyHidden](https://github.com/Booyaka101/whyhidden). This is the third side
of the same idea: the dev tool tells addon authors which calls go dark, WhyHidden
tells players what is hidden, and ClearCombatText makes what is *not* hidden
readable again.

## Development

`npm install && npm test` runs the addon under a Lua VM against a stubbed client:
event pump, consolidation window, flush, render and guard behaviour are all
asserted headlessly.

## License

MIT
