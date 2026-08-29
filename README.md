# OpenLogi for Omarchy

A bar plugin that shows [OpenLogi](https://github.com/AprilNEA/OpenLogi) agent status and device battery on Linux. OpenLogi has a tray on macOS and Windows; this is that tray for the Omarchy bar. Button maps and DPI stay in the OpenLogi app.

## Features

- Dims the bar icon when the agent is off; tints it when a device battery is low.
- Lists connected devices with kind and battery, read-only.
- Starts, stops, and restarts `openlogi-agent`.
- Opens `openlogi-desktop` for configuration.
- Polls every 30 seconds. Right-click the icon to refresh now.

## Requirements

- Omarchy with shell plugins.
- [OpenLogi](https://github.com/AprilNEA/OpenLogi) 0.7.4 or newer (`openlogi`, `openlogi-desktop`, `openlogi-agent`).
- `python3`.

OpenLogi is not in the Omarchy package set yet. Install the upstream Arch package from [OpenLogi releases](https://github.com/AprilNEA/OpenLogi/releases). Confirm:

```bash
openlogi --version
systemctl --user is-active openlogi-agent.service
```

If the agent is inactive, start it from the plugin panel or enable **Start at login** in the OpenLogi app.

## Install

```bash
omarchy plugin add https://github.com/shawnyeager/openlogi-omarchy.git --enable
```

The widget lands on the right. To move it:

```bash
omarchy bar move openlogi-omarchy
```

To install the OpenLogi package and this plugin from a checkout:

```bash
./install.sh
```

If an older `openlogi.bar` copy is still installed:

```bash
omarchy plugin remove openlogi.bar
```

## Usage

- Left-click the icon to open or close the panel.
- Middle-click to launch OpenLogi.
- Right-click to refresh.
- Use the header switch, or press `A`, to start or stop the agent.
- Press `C` or `S` to open OpenLogi, `R` to refresh, `Esc` to close.
- Arrow keys move through devices and actions; Enter activates the selection.

On Linux, Configure and Settings both launch the desktop app. There is no `openlogi://` handler.

## Update

```bash
omarchy plugin update openlogi-omarchy
```

## Remove

```bash
omarchy plugin remove openlogi-omarchy
```

Removing the plugin does not uninstall OpenLogi or change its config.

## Commands

The plugin runs these local commands. It does not read OpenLogi credentials or talk to the network.

```text
python3 status.py
systemctl --user enable --now openlogi-agent.service
systemctl --user stop openlogi-agent.service
systemctl --user restart openlogi-agent.service
uwsm-app -- /usr/bin/openlogi-desktop
```

`status.py` calls `openlogi list` and checks whether the agent unit and socket are present.

## License

MIT. [OpenLogi](https://github.com/AprilNEA/OpenLogi) is licensed separately.
