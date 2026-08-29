# Development

## Checks that run outside the game

The addon cannot be executed outside WoW, so these two are the only automated feedback there is.
Both run from the repo root:

```sh
luacheck .      # static analysis; the WoW globals are declared in .luacheckrc
busted          # unit tests in tests/, configured by .busted
```

Install them with `luarocks install luacheck` and `luarocks install busted`.

### luacheck

`.luacheckrc` declares the WoW client's global namespace, so reading `C_Item` or `GetMoneyString` is
fine while _writing_ any of them is flagged. The vendored `libs/` tree is excluded - it is not ours.

It matters most when moving code between files. The report is a set of helpers forward-declared at the
top of the file, so `function name()` there assigns to a local. Miss a name out of the declaration
block and Lua silently creates a global instead, which keeps working until two files declare the same
name and start overwriting each other. luacheck catches that immediately; the game never will.

luacheck looks for `.luacheckrc` in the current directory, not next to the files it is given, so run it
from the repo root or it will lint `libs/` too.

## How the report is put together

Three files, and the split is what keeps each of them readable:

- `MyLootHistoryData.lua` - the filter state and everything derived from the history: the item and
  currency lists, the gold total, the activity buckets, the dropdown contents and the CSV. It knows
  nothing about frames, which is why `filters_spec` can test all of it directly.
- `MyLootHistoryUIKit.lua` - the look, and every control the window is built out of. Panels, buttons,
  a search box, a dropdown, a toggle, a segmented control and a scrollbar, all drawn from plain
  textures rather than the Blizzard templates. It knows nothing about loot.
- `MyLootHistoryUI.lua` - the window, which is the only file that knows about both.

Two things there are easy to break. The list is **virtualised**: there is one frame per row that fits
on screen, refilled as you scroll, so `fillRow` has to re-dress a pooled frame completely rather than
patch it - anything it forgets to set is left over from whatever that frame was showing before. And
the header cells and the row cells both lay themselves out from `columnLayout()`, so a column added
in one place and not the other slides the two apart.

## Tests

`busted` runs everything in `tests/` matching `_spec`.

- `tests/dateutils_spec.lua` - the date ranges behind every filter in the report
- `tests/prune_spec.lua` - retention, the only code in the addon that deletes a player's history, plus
  the `itemId -> index` map that has to be invalidated when pruning shifts record positions
- `tests/aggregate_spec.lua` - `MLH:aggregateLoot`, which the rows, the export and the tooltip all
  agree through
- `tests/filters_spec.lua` - the filter state and everything `MLH:buildReport` selects with it
- `tests/report_spec.lua` - the report window itself, built and then clicked on

`tests/support/wow.lua` is a small stub of the client API with a **freezable clock**, so a date
assertion means the same thing whatever day the suite runs on. It also fakes LibStub, AceDB,
AceLocale and AceAddon - just enough for a module to load and register itself.

`tests/support/frames.lua` is the same idea for the widget API: frames that remember their size,
their scripts and their children, and a `Fire` that runs a script's handlers the way the client
would. It is what makes the report testable at all - `report_spec` opens the window, scrolls it,
clicks every column header, opens both dropdowns and resizes it, and a mistyped method is a red test
instead of an error the first time someone logs in.

Two things about the mock are worth knowing before extending it. It only synthesises **PascalCase**
methods, so reading an unset lowercase field still answers nil - otherwise `if row.entry then` would
be true for every frame there is. And `SetScript` **replaces** what `HookScript` registered, exactly
as it does in the client: a widget that hooks a script and then sets it silently loses the hook.

### `defect()`

A few tests are wrapped in `defect()` (`tests/support/defect.lua`). These describe behaviour that is
**wrong today**: the body asserts what the function _should_ do, and the wrapper expects it to fail.
The suite stays green while the bug stands, and turns red the moment someone fixes it - at which point
the test should be rewritten as an ordinary `it`.

`it` has to be handed in - `require("tests.support.defect")(it)` - because busted puts `it` in each
spec file's own environment rather than in `_G`, so a required module cannot reach it.

## Packaging

`tools/` holds the CurseForge packaging scripts. Both run luacheck and the tests first - luacheck as a
warning, a failing test as a hard stop - and the two produce the same zip.

```sh
./tools/build.sh                      # macOS / Linux
.\tools\build.ps1                     # Windows
./tools/build.sh --version 1.5.0      # also rewrites ## Version in the .toc
./tools/build.sh --clean              # wipe dist/ first
./tools/build.sh --help
```

If PowerShell's execution policy blocks the script:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build.ps1
```

### What gets packaged

The scripts copy from the filesystem rather than from git, so being gitignored is _not_ enough to keep
a file out of the zip. Exclusion works three ways:

1. **anything whose name starts with a dot**, at any depth - `.git`, `.github`, `.vscode`, `.claude`,
   `.luacheckrc`, `.busted`, `.gitignore`, `.DS_Store`, and any tool config added later
2. **`EXCLUDE_DIRS`** - `dist`, `node_modules`, `tests`, `tools`
3. **`EXCLUDE_FILES`** - `DEVELOPMENT.md`, `AUDIT.html`

`README.md`, `CHANGELOG.md` and `LICENSE.md` do ship: the first two are read by players on the addon
page, and the `.toc` points at the licence for the GPL notice.

`libs/` ships as vendored, including the upstream `ace3-license.txt` and the LibDataBroker readme and
changelog. Those are how the libraries are distributed, and trimming files out of a vendored tree only
makes the next update harder to diff.

After changing anything about exclusion, check the result:

```sh
unzip -l dist/MyLootHistory-*.zip
```

## In-game smoke checks

luacheck and the tests cannot see the parts of the addon that matter most to a player, so this list is
the real integration test. Run it after any change that touches the report, the loot handlers or the
saved data:

1. loot a single item
2. loot a stack of something
3. loot copper
4. loot a currency
5. open the report - rows, icons, values all present
6. each date range in the dropdown
7. each column header sorts, and again for the reverse direction
8. the search box filters
9. the zone dropdown filters
10. Export produces CSV matching what is on screen
11. `/reload`, then confirm the history survived
12. a fresh character sees an empty report rather than an error

For a refactor that should change nothing a player can see, the CSV export doubles as a golden master:
set the range to "All the time", export and save the text before the change, export again afterwards,
and diff the two. An empty diff covers filtering, aggregation, sorting and pricing in one step.
