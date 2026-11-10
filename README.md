# deliver-a-gift

Roblox game built with [Rojo](https://rojo.space).

## Development

1. Install the toolchain: `rokit install`
2. Install packages: `wally install`
3. Start syncing: `rojo serve`
4. In Roblox Studio, connect with the Rojo plugin (`rojo plugin install` once).

## Structure

Rules of the game live in `CLAUDE.md`. All numbers live in `src/shared/Config.luau`.

- `src/shared` → ReplicatedStorage — Config, Elves, ElfVisuals, Remotes
- `src/server` → ServerScriptService — `Main.server.luau` boots the modules in `Systems/`
- `src/client` → StarterPlayer/StarterPlayerScripts — HUD and effects
- `src/gui/AnnounceGui` → StarterGui/AnnounceGui — AnnounceClient
- `ServerPackages` → ServerScriptService/ServerPackages — Wally server packages (ProfileStore, not used yet)

The map (workshops, sleigh, districts) is built by `Systems/World.luau` at server start.
Instances that are not in `src/` live only in the place file; Rojo leaves them alone
(`$ignoreUnknownInstances`).

## Checks

- Format: `stylua src`
- Lint: `selene src`
