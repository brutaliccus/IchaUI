# IchaUI 3.5.0 — stance kit API

Action bars no longer page by adding an offset to the action slot id. Each stance stores a kit. Changing stance (or `/icha stance sim`) saves the bar you are leaving and places the next kit onto the bar's own slots. Hero 1 still uses `heroPages`. Drawers do not follow stance.

## Slot id

`IchaUI_GetPagedID(buttonId [, barId])` returns `buttonId`. It does not apply `mod(id + size * offset, 120)`.

`IchaUI_StanceOffset(barIndex)` always returns `0`.

`IchaUI_StanceSetMap(barIndex, stanceId, offset)` does nothing. Saved `actionMaps` offsets are ignored (not converted).

## Kits

`IchaUIDB.stance.actionKits[barIndex][stanceId]` is `{ slots = { [1] = snap, ... } }`.

Index 1 is the bar's first owned slot. A snap is one of:

- `{ empty = 1 }`
- `{ kind = "spell", spell = name, rank = "Rank N", texture = path }`
- `{ kind = "item", itemId = id, spell = name, texture = path }`
- `{ kind = "macro", spell = macroName, texture = path }`

`IchaUIDB.stance.applied` is the stance whose kit is currently placed in the live slots.

On first load, page 0 and the form you are in are copied from the live buttons. Every other page starts empty. Edits stick when you leave the page, log out, or zone.

`IchaUI_StanceCopyKits(fromId, toId [, barIndex])` copies kits. Omit `barIndex` to copy every action bar.

`IchaUI_StanceClearKits(stanceId [, barIndex])` empties those kits. If that page is showing, the buttons clear too.

## Unchanged

`IchaUI_StanceState`, `IchaUI_StanceName`, `IchaUI_StanceSetSim`, `IchaUI_StanceSetEnabled`, `IchaUI_StanceClassIds`, `IchaUI_StanceOnChange`, `IchaUI_StanceFire`, `IchaUI_StanceSlash`, `IchaUI_BuildStanceOptions`.

`IchaUI_HeroLivePage` and `IchaUI_HeroEnsureStancePages` still swap `IchaUIDB.stance.heroPages` onto `IchaUIDB.heroSetup`. `IchaUI_HeroSyncIcons()` places that page onto the hero buttons.

`IchaUIDB.stance.drawerFollowHero` is forced off. Stance changes do not call `IchaUI_CustomDrawers_Apply`.
