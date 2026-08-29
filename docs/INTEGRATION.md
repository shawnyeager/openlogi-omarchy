# Omarchy + OpenLogi integration — research & plan

Handoff doc for continuing integration work. Written after the bar plugin shipped and the app-launch bug was fixed.

## What's done

| Item | Status |
|------|--------|
| Quickshell bar plugin (`openlogi-omarchy`) | Repo-root manifest; `omarchy plugin add` |
| GitHub repo | https://github.com/shawnyeager/openlogi-omarchy |
| Install script | Downloads upstream `.pkg.tar.zst` from GitHub releases |
| Configure/Settings launch | Fixed — `Quickshell.execDetached(["uwsm-app", "--", "/usr/bin/openlogi-desktop"])` |
| Browser focus bug | Root cause: `omarchy-launch-or-focus openlogi` matched Chromium tab title "OpenLogi" (GitHub page) |

### Plugin scope (intentional)

Tray surrogate only — not a mini Logi Options+:

- Agent on/off, health warnings, read-only device telemetry
- Launch `openlogi-desktop` for all configuration
- Out of scope: button maps, DPI, pairing UI, settings editor

## OpenLogi on this system

```
Package:     openlogi 0.7.4-1 (from upstream GitHub release .pkg.tar.zst)
Binaries:    openlogi, openlogi-desktop, openlogi-agent, openlogi-overlay
Config:      ~/.config/openlogi/config.toml
Agent unit:  /usr/lib/systemd/user/openlogi-agent.service (packaged)
             ~/.config/systemd/user/openlogi-agent.service (written by app when launch_at_login=true)
Socket:      $XDG_RUNTIME_DIR/openlogi/agent.sock
Desktop:     StartupWMClass=org.openlogi.openlogi
```

### Config ownership issue

`~/.config/openlogi/` was owned by **root** (likely from running the app with sudo during manual install). That caused `Permission denied` on lock files.

```bash
sudo chown -R "$USER:$USER" ~/.config/openlogi/
```

### Current `config.toml` (relevant fields)

```toml
[app_settings]
launch_at_login = true          # On Linux: writes ~/.config/systemd/user/openlogi-agent.service
check_for_updates = false       # Should stay off when using pacman
auto_install_updates = false
update_prompt_seen = true
appearance = "system"           # system | light | dark
# theme_light / theme_dark — optional gpui-component theme names
```

## Integration topics (not yet implemented)

### 1. Agent vs "Start at login"

**They are the same thing on Linux.** OpenLogi's `launch_at_login` is implemented in `openlogi-agent/src/launch_agent.rs`:

- When `true`: writes `~/.config/systemd/user/openlogi-agent.service`, `daemon-reload`, `systemctl --user enable`
- When `false`: disables and removes the user unit file
- Packaged unit at `/usr/lib/systemd/user/openlogi-agent.service` also exists

**Recommendation:** Pick one path, don't double-enable:

- **Preferred:** `launch_at_login = true` in config — let OpenLogi reconcile systemd (matches macOS/Windows UX)
- **Alternative:** `launch_at_login = false` + `systemctl --user enable --now openlogi-agent.service` using the packaged unit only

`install.sh` currently does both (manual `systemctl enable` AND leaves `launch_at_login` to the user). Consolidate in `omarchy-openlogi-sync`.

### 2. Pacman vs in-app updater

From `openlogi-desktop` strings and `settings.rs`:

- `check_for_updates` — one GitHub release check per launch when enabled
- `auto_install_updates` — downloads/stages update; **"update install is not supported on this platform"** on Linux
- In-app updater uses gpui-updater; won't override pacman

**Recommendation for Omarchy users:**

```toml
check_for_updates = false
auto_install_updates = false
update_prompt_seen = true
```

Document: update via `omarchy update` / `pacman -Syu openlogi`. Optional `post-update.d` hook to notify if openlogi was upgraded.

### 3. Theme sync with Omarchy

**Omarchy theme location:**

```
~/.local/state/omarchy/current/theme/colors.toml   # active theme
~/.local/state/omarchy/current/theme.name            # human name, e.g. "Retro 82"
```

`colors.toml` has `mode = "dark"` | `"light"` plus accent/background palette.

**OpenLogi appearance model** (`openlogi-core/src/config/settings.rs`):

- `appearance`: `system` | `light` | `dark`
- `theme_light` / `theme_dark`: optional gpui-component theme names (e.g. `"OpenLogi Light"`, `"OpenLogi Dark"`)
- Built-in themes registered in `openlogi-desktop/src/ui/theme.rs` from bundled JSON
- No API to inject arbitrary Omarchy hex colors without generating a custom gpui theme JSON

**Realistic v1 sync** (via `omarchy hook install theme-set`):

1. Read `~/.local/state/omarchy/current/theme/colors.toml`
2. Map `mode` → OpenLogi `appearance` (`dark` / `light`; skip `system` so Omarchy is source of truth)
3. Restart not required for config.toml — takes effect on next `openlogi-desktop` launch / agent read

**Future v2:** Generate gpui-component theme JSON from Omarchy `colors.toml` (accent, background, foreground, muted) and set `theme_light`/`theme_dark` to a custom "Omarchy" theme name. Requires either upstream support for external theme files or shipping a generated JSON in `~/.config/openlogi/`.

**Hook pattern** (from Omarchy skill):

```bash
# ~/.config/omarchy/hooks/theme-set.d/openlogi.sh
#!/bin/bash
THEME_NAME="$1"
/path/to/omarchy-openlogi-sync --theme-only
```

### 4. Package for `pkgs.omarchy.org`

Omarchy pacman repo:

```ini
[omarchy]
Server = https://pkgs.omarchy.org/stable/$arch
# edge: https://pkgs.omarchy.org/edge/$arch
```

Build system: **https://github.com/omacom-io/omarchy-pkgs**

```
pkgbuilds/
  <package>/
    PKGBUILD
    .omarchy/package.json    # source metadata, release ring
```

Package tiers: `stable` (manual promote), `edge` (daily AUR sync), `shared` (both).

OpenLogi upstream already publishes signed Arch packages:

```
https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.4/
  openlogi-v0.7.4-linux-amd64.pkg.tar.zst   sha256: 40785d2c...
  openlogi-v0.7.4-linux-arm64.pkg.tar.zst   sha256: d9612bc4...
```

Upstream builds via `cargo run -p xtask -- linux package` + nfpm (`packaging/linux/nfpm.yaml`).

**Two packaging options for omarchy-pkgs:**

| Approach | Pros | Cons |
|----------|------|------|
| **Repackage upstream `.pkg.tar.zst`** | Fast CI, matches upstream binaries, verified SHA256 | No Omarchy-specific patches in the package itself |
| **Build from source (cargo + nfpm)** | Full control, can patch | Long builds, Rust dep churn |

**Recommended for v1:** Repackage upstream release in `pkgbuilds/edge/openlogi/` (or `shared/` once stable), with `.omarchy/package.json`:

```json
{
  "source": "local",
  "release_ring": "edge"
}
```

Draft PKGBUILD sketch:

```bash
pkgver=0.7.4
# source_x86_64 = upstream .pkg.tar.zst
# package() { bsdtar -xpf ... -C "$pkgdir" }
```

**PR target:** `omacom-io/omarchy-pkgs` — not this repo. This repo can hold the draft PKGBUILD under `packaging/omarchy-pkgs/openlogi/` for copy-paste.

### 5. `omarchy install service openlogi` (upstream Omarchy)

Pattern from existing services (`omarchy-install-service-signal`, `dropbox`):

```bash
omarchy-pkg-add openlogi          # once in omarchy repo
omarchy plugin enable openlogi-omarchy
omarchy-openlogi-sync             # config + hooks
setsid uwsm-app -- gtk-launch openlogi &
```

Dropbox also enables its bar plugin in the install script. OpenLogi should do the same.

**Requires:**

1. `openlogi` in omarchy-pkgs (edge first)
2. PR to `basecamp/omarchy` adding `omarchy-install-service-openlogi` (or contribute via omarchy-pkgs if that's where install scripts live — they're in `/usr/share/omarchy/bin/` from the main omarchy package)

This plugin repo is the right home for the install script + sync + hooks until first-party integration lands.

## Proposed repo layout (next session)

```
openlogi-omarchy/
├── manifest.json                    # Omarchy plugin contract (repo root)
├── packaging/omarchy-pkgs/openlogi/   # draft PKGBUILD — ready for omarchy-pkgs PR
├── bin/omarchy-openlogi-sync        # config + theme + agent reconcile
├── lib/openlogi_sync.py             # sync implementation
├── hooks/theme-set-openlogi.sh      # installed via omarchy hook install
├── tests/                           # parser + sync unit tests (CI)
├── install.sh
└── docs/INTEGRATION.md
```

**Implemented (cloud, pending on-machine test):** items above except omarchy-pkgs PR and first-party `omarchy install service`.

## `omarchy-openlogi-sync` behavior (to implement)

1. Ensure `~/.config/openlogi/` owned by `$USER`
2. Set pacman-friendly update flags in `config.toml` (TOML merge or python helper)
3. Set `launch_at_login = true` (or document single-path choice)
4. Sync `appearance` from Omarchy `colors.toml` `mode`
5. Install theme-set hook if missing
6. Optionally restart agent: `systemctl --user restart openlogi-agent.service`

Use **python3** for TOML edits (stdlib `tomllib` 3.11+ or preserve manual like upstream) — `config.toml` uses `schema_version = 4`.

## Cloud agent limitations

This work **cannot run fully in a cloud agent**:

- No Omarchy desktop / Hyprland / Quickshell to test the bar plugin
- No Logitech HID++ devices for `openlogi list` parsing validation
- `sudo` / `systemctl --user` / `omarchy theme set` need the real machine
- `omarchy-pkgs` PR build/sign/promote happens on Omarchy infra, not locally without keys

**Test on the real machine:**

```bash
./install.sh
omarchy restart shell
# click Configure — should open openlogi-desktop, not browser
openlogi list                    # with mouse plugged in
omarchy-openlogi-sync            # once implemented
omarchy theme set "Tokyo Night"   # verify theme hook updates config.toml
```

## Open questions for tomorrow

1. **omarchy-pkgs PR** — edge first, or ask maintainers for `shared`/stable?
2. **Theme v1** — `appearance` only, or invest in gpui JSON generation?
3. **First-party** — PR `omarchy-install-service-openlogi` to basecamp/omarchy, or stay userland in this repo?
4. **Plugin ownership** — keep `openlogi-omarchy` as a third-party plugin, or eventually `omarchy.openlogi` in main Omarchy shell?

## References

- OpenLogi: https://github.com/AprilNEA/OpenLogi
- Omarchy pkgs: https://github.com/omacom-io/omarchy-pkgs
- Omarchy pacman.conf: `/usr/share/omarchy/default/pacman/pacman-stable.conf` (`[omarchy]` repo)
- OpenLogi launch_agent (Linux systemd): `crates/openlogi-agent/src/launch_agent.rs`
- OpenLogi settings schema: `crates/openlogi-core/src/config/settings.rs`
- Omarchy hooks: `~/.config/omarchy/hooks/theme-set.d/`
