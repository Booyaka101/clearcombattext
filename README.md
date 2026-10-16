# ClearCombatText

Scrolling combat text that stays readable under the secret-value API.

ClearCombatText uses Blizzard's `C_CombatText` API to display incoming combat text
for your player or vehicle. It separates damage taken from heals and gains. It
does not read the combat log, reconstruct outgoing per-spell damage, or bypass
secret-value restrictions.

- **Two independent scroll areas.** Damage taken and harmful effects start on
  the left; heals, resources and other gains start on the right. Move either area
  separately and choose its scroll direction.
- **Public-value consolidation.** Repeats inside 0.45 seconds merge into a sum:
  three 340 hits become `1020 x3`. Secret combat amounts display individually;
  they cannot be added together. Resource kinds consolidate separately.
- **Crits you can see.** Criticals render larger with a pop, in their own color.
- **Combat vocabulary.** Direct and periodic heals, shields, mitigation, avoidance,
  resource gains, aura gains and fades, and combat enter/leave.

## Commands

- `/cct test`: preview the styling with sample events
- `/cct anchor`: show both boxes, or lock both if both are already visible
- `/cct anchor incoming` or `/cct anchor gains`: toggle just one box; repeat to lock
- `/cct direction incoming down`: set a stream's direction; accepts `incoming`
  or `gains` and `up`, `down`, `left` or `right`
- `/cct reset`: reset both positions and directions
- `/cct blizz`: explicitly toggle Blizzard's floating combat text
- `/cct`: status and command help

Tip: turn Blizzard's own floating combat text off (Interface → Combat) or you will
see both. Settings are only changed when you explicitly run `/cct blizz`.

## Compatibility

Built for the WoW Forever beta (interface 16001) and Midnight retail (12.1.0 and
12.1.5). On clients without `C_CombatText` it stays inert. Missing event APIs are
checked before use. Combat event handling uses no protected calls or per-event
probe closures. A protected call remains for infrequent unit binding.

Secret payloads are passed to the text widget without length checks, comparisons
against their contents, or arithmetic. Consolidation only uses values confirmed
public by `issecretvalue`. On older betas without that detector, all combat
payloads are display-only and consolidation is disabled. Existing shared-anchor
settings migrate to two separate positions on first login.

At most 128 lines animate at once. Extra new lines are skipped while that limit
is reached; existing public consolidation still updates. The widget pool is
reused, the update frame sleeps when idle, and settled crits do not rewrite their
font size each frame.

## Honest limits

The API does not supply spell identifiers for per-spell icons. Low-health,
low-mana and rune-readiness detection are not implemented. A partial mitigation
line shows damage taken and the mitigated amount; secret critical flags are not
inspected. Resource colors are only selected when the resource token is public.

From the author of [wow-secret-lint](https://github.com/Booyaka101/wow-secret-lint)
and [WhyHidden](https://github.com/Booyaka101/whyhidden). This is the third side
of the same idea: the dev tool tells addon authors which calls go dark, WhyHidden
tells players what is hidden, and ClearCombatText makes what is *not* hidden
readable again.

## Development

`npm ci` followed by `npm test` runs pipeline and regression suites, plus fresh-VM
startup fixtures for saved positions, edge/corner migration and invalid settings.
Coverage includes Blizzard-shaped heal payloads, secret display paths, vehicle
binding, resource grouping, lock states, a 2,000-event burst, expiry and pool reuse.

Payload mappings follow Blizzard's
[combat-text handler](https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_CombatText/Shared/CombatText.lua).
The headless harness is not a native WoW secret/taint emulator. Forever Beta and
Midnight in-game verification remains required before release.

## License

MIT
