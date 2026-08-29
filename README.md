# openlogi-omarchy

An [Omarchy](https://omarchy.org/) shell plugin that brings [OpenLogi](https://github.com/AprilNEA/OpenLogi) to the status bar on Linux.

OpenLogi ships a system tray on macOS and Windows. On Linux there is no tray icon, so this plugin acts as a **tray surrogate**: agent health, device telemetry, and a launcher for the desktop app. Button remapping, DPI, and other configuration stay in OpenLogi itself.

## Features

- **Bar icon** — dim when the agent is off; warning tint when any device battery is low
- **Panel** — agent toggle, health warnings, read-only device list (name, kind, battery)
- **Actions** — open OpenLogi, restart the background agent
- **Clicks** — left opens the panel, middle opens the app, right refreshes status

## Requirements

- [Omarchy](https://omarchy.org/) with the Quickshell bar (`omarchy-shell`)
- [OpenLogi](https://github.com/AprilNEA/OpenLogi) `0.7.4+` (Arch package or manual install)
- `python3` (for the status helper script)

## Install

Install OpenLogi if it is not already present, then add the plugin from git:

```bash
omarchy pkg add openlogi   # or install the upstream Arch package
omarchy plugin add https://github.com/shawnyeager/openlogi-omarchy.git --enable
```

`omarchy plugin add` clones this repository, validates `manifest.json` at the repo root, and places the widget on the right by default.

To also sync OpenLogi config (pacman-friendly updates, agent autostart, theme hook) from a local checkout:

```bash
git clone https://github.com/shawnyeager/openlogi-omarchy.git
cd openlogi-omarchy
./install.sh
```

`install.sh` installs the OpenLogi package if needed, runs `omarchy-openlogi-sync`, and adds this checkout with `omarchy plugin add`.

## Remove

```bash
omarchy plugin remove openlogi-omarchy
```

That disables the widget and deletes the git checkout under `~/.config/omarchy/plugins/openlogi-omarchy/`. It does not uninstall the OpenLogi application.

If you previously installed the old `openlogi.bar` copy, remove it first:

```bash
omarchy plugin remove openlogi.bar
```

## Usage

| Interaction | Action |
|-------------|--------|
| Left click bar icon | Open panel |
| Middle click | Launch `openlogi-desktop` |
| Right click | Refresh device status |
| `c` / `s` in panel | Open OpenLogi |
| `r` in panel | Refresh |
| `a` in panel | Toggle agent |

Configure buttons, DPI, and profiles in the OpenLogi app — not in this panel.

## Background agent

OpenLogi needs `openlogi-agent` running for remapping and HID++ control. On Linux, **Start at login** in the app (`launch_at_login` in `~/.config/openlogi/config.toml`) writes and enables `~/.config/systemd/user/openlogi-agent.service`.

`omarchy-openlogi-sync` sets `launch_at_login = true` and restarts the agent — you do not need a separate manual `systemctl enable`.

```bash
./bin/omarchy-openlogi-sync              # full sync
./bin/omarchy-openlogi-sync --theme-only # after omarchy theme set
```

## Linux limitations

- **No `openlogi://` deeplinks** — URL handlers are not registered on Linux, so Configure/Settings both launch the main app window.
- **Updates** — use `pacman` / `omarchy update` for the installed package; OpenLogi's in-app updater targets release installs, not the Arch package.
- **Themes** — OpenLogi appearance is independent of Omarchy themes today. See [docs/INTEGRATION.md](docs/INTEGRATION.md) for the planned sync.

## Omarchy package mirror (planned)

OpenLogi should ship on [pkgs.omarchy.org](https://pkgs.omarchy.org) via [omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs), not GitHub release downloads. Draft PKGBUILD and integration plan: [docs/INTEGRATION.md](docs/INTEGRATION.md).

Until then, `install.sh` falls back to the upstream GitHub `.pkg.tar.zst`.

## Project layout

```
manifest.json      # Omarchy plugin contract (repo root)
Panel.qml          # Bar widget + details panel
Service.qml        # Status polling and agent control
status.py          # OpenLogi CLI helper
bin/               # omarchy-openlogi-sync
lib/               # Python sync logic
hooks/             # theme-set hook for omarchy hook install
packaging/         # draft PKGBUILD for omarchy-pkgs PR
tests/             # parser, sync, and publish-layout tests
install.sh         # optional OpenLogi package + plugin add
```

## Troubleshooting

**Plugin missing from the bar**

```bash
omarchy plugin enable openlogi-omarchy --section right
omarchy restart shell
```

**Panel shows load errors**

```bash
journalctl --user -u omarchy-shell -n 50 --no-pager
omarchy-shell shell rescanPlugins
```

**Configure opens the browser**

Linux has no `openlogi://` handler. Ensure you are on a recent plugin build that launches `/usr/bin/openlogi-desktop` directly, then restart the shell:

```bash
omarchy restart shell
```

## License

MIT — see [LICENSE](LICENSE). The [OpenLogi](https://github.com/AprilNEA/OpenLogi) application has its own license.
