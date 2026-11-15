# Tests

These run the real addon files outside the game, against a small simulated
World of Warcraft (`wowsim.lua`): bags, a vendor with payments and a buyback
list, loot windows, mail, units, the cursor, timers and events. `test.lua` plays
through scenarios and checks the results.

They need a Lua 5.3+ interpreter. The Lua language server that ships with the
VS Code "Lua" extension (sumneko) can run scripts, so nothing extra has to be
installed:

```
"<path to>/lua-language-server.exe" tests/test.lua "<path to this repo>"
```

With a regular Lua install it is `lua tests/test.lua .` from the repo root.
GitHub runs the same command on every push and pull request
(`.github/workflows/test.yml`).

The last line prints `N passed, 0 failed`. A failing check prints `FAIL:` with
what it expected.

The simulation only knows what the addon uses. It cannot show how things look
in game, so frame layout and artwork still need a look in the real client.

This folder is left out of release zips (see `.gitattributes`).
