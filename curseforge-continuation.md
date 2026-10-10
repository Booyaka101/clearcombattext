# ClearCombatText — CurseForge continuation (one 10-second manual step)

Wizard state RIGHT NOW (verified 2026-10-10): authors.curseforge.com → Create Project →
**General step filled** — game: World of Warcraft, name: ClearCombatText, summary set.
The tab is open in Chrome.

## The one manual step

Chrome (updated since Oct 7) refuses to open OS file dialogs from automated input.
In the open tab:

1. Click **Upload image** → pick `C:\Users\cbosc\AppData\Local\Temp\opencode\cct-logo.png`
2. Click **Save As Logo** in the crop dialog
3. Tell the agent "logo done"

Everything after that is automated and proven on WhyHidden's run: category (Combat),
description (release notes), custom license (MIT text), distribution (allow 3rd party),
Create, then the zip upload with game versions 1.60.1 / 12.1.5 / 12.1.0, channel Beta.
The zip is built and waiting at
`C:\Users\cbosc\AppData\Local\Temp\opencode\ClearCombatText-0.3.0.zip`.

## Why the tab must stay open

The wizard lives in the tab; closing it loses the filled General step. If lost,
the agent can re-fill it in ~30 seconds (game tile click + name/summary injection
are scripted).
