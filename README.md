# ClearCombatText

Scrolling combat text that stays readable under the secret-value API.

ClearCombatText uses Blizzard's `C_CombatText` API to display incoming combat text
for your player or vehicle. It separates damage taken from heals and gains. It
does not read the combat log, reconstruct outgoing per-spell damage, or bypass
secret-value restrictions.

- **Two independent scroll areas.** Damage taken and harmful effects start on
  the left; heals, resources and other gains start on the right. Move either area
  separately and choose its scroll direction.
- **Public-value consolidation.** Repeats within 0.45 seconds of the first hit
  merge into a sum: three 340 hits become `1020 x3`. Secret amounts display individually;
  they cannot be added together. Resource kinds consolidate separately.
- **Crits you can see.** Criticals render larger with a pop, in their own color.
- **Combat vocabulary.** Direct and periodic heals, shields, mitigation, avoidance,
  resource gains, aura gains and fades, and combat enter/leave.
- **Predictable spacing.** Vertical text stacks ahead of newer lines; horizontal
  text uses separate rows. Layout never measures widgets that displayed secrets.
- **Visual settings.** Font, outline, shadow, opacity, crit emphasis and optional
  area colors, with previews and independent duration, travel and spacing controls.
  The panel scales to fit the screen. Hex color drafts survive unrelated edits;
  Apply saves them and Escape discards the draft.
- **Noise controls.** Toggle periodic damage/healing, resources, auras, avoidance
  and combat-state notifications using public event categories.
- **Presets and profiles.** Readable, Minimal and Healer presets retain positions.
  Up to ten named profiles also save both positions and directions.
  Overwrite and delete require confirmation in the panel; explicit slash commands
  act immediately.

## Commands

- `/cct config`: open or close settings; changes save immediately and preview
- `/cct test`: preview the styling with sample events, even when disabled
- `/cct burst`: run a five-second burst preview using the current filters
- `/cct toggle`: enable or disable event display without changing Blizzard settings
- `/cct anchor`: show both boxes, or lock both if both are already visible
- `/cct anchor incoming` or `/cct anchor gains`: toggle just one box; repeat to lock
- `/cct direction incoming down`: set a stream's direction; accepts `incoming`
  or `gains` and `up`, `down`, `left` or `right`
- `/cct reset`: reset both positions and directions
- `/cct blizz`: explicitly toggle Blizzard's floating combat text
- `/cct preset readable` (or `minimal`, `healer`): apply a preset, retaining positions
- `/cct profile save My Raid`: save or overwrite a named profile
- `/cct profile load My Raid`: restore settings, positions and directions
- `/cct profile delete My Raid`: remove that saved profile only
- `/cct profile list`: list saved profiles; names are case-sensitive, up to 32
  letters, numbers, spaces, underscores or hyphens
- `/cct`: status and command help

`/clearcombattext` is an alternative if another addon claims `/cct`.

Demo text is labeled `[Preview]` and always ranks below real events. Starting a
new preview replaces the previous demo; closing settings stops its demo without
removing live combat text.

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

By default each area displays up to eight lines, configurable from 4 to 64 per
area, with an overall 128-line ceiling. At capacity, crits and supported low-health
or low-mana messages can replace lower-priority lines in that area. Equal-priority
overflow is skipped; existing public consolidation still updates. Consolidation
does not rewind animation or extend a line indefinitely. The widget pool is
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
Settings coverage includes profile snapshots, category filters before payload
access, mixed-size spacing in all directions, priority replacement, preview
termination and UI callbacks. Review fixtures cover expiry before the next update,
fixed consolidation windows, preview isolation, maximum-size row reuse, screen
resizing, draft preservation and profile confirmations. `npm run test:mutations`
also verifies that fourteen deliberate regressions are rejected by the tests.

Payload mappings follow Blizzard's
[combat-text handler](https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_CombatText/Shared/CombatText.lua).
The headless harness is not a native WoW secret/taint emulator. Forever Beta and
Midnight in-game verification remains required before release.

## License

MIT
