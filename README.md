# deliver-a-gift

Roblox game built with [Rojo](https://rojo.space).

## Development

1. Install the toolchain: `rokit install`
2. Install packages: `wally install`
3. Start syncing: `rojo serve`
4. In Roblox Studio, connect with the Rojo plugin (`rojo plugin install` once).

## Structure

Paths match the existing place, so `require` calls keep working.

- `src/shared` → ReplicatedStorage — DragonConfig, DragonVisuals
- `src/server` → ServerScriptService — PlayerData, EggSystem, BaseSystem
- `src/client` → StarterPlayer/StarterPlayerScripts — DragonAnimator
- `src/gui/AnnounceGui` → StarterGui/AnnounceGui — AnnounceClient
- `ServerPackages` → ServerScriptService/ServerPackages — Wally server packages (ProfileStore)

Instances that are not in `src/` (RemoteEvents, GUI labels, Workspace) live only in the
place file; Rojo leaves them alone (`$ignoreUnknownInstances`).

## Checks

- Format: `stylua src`
- Lint: `selene src`
