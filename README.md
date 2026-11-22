# CCast - A native fast launcher for MacOS
Built with obj-C and C++, without AI things inside (if you want them, just use raycast or something else, idc/k).

## Build

To build the launcher binary:
```bash
make
```

To package it into a macOS application bundle (`CCast.app`):
```bash
make app
```

To create the installer disk image (`CCast.dmg`):
```bash
make dmg
```

To run the unit tests:
```bash
make test
```

## Usage
Press `Option + Space` (`⌥ Space`) to open or hide the launcher.

- **Applications (default):** Type to fuzzy-search installed apps and press `Enter` to launch.
- **File mode (`/`):** Type `/` to browse and search files. Press `Tab` to autocomplete directories/files and `Enter` to reveal in Finder.
- **Clipboard mode (`:`):** Type `:` to view and search clipboard history (text, images/screenshots, and copied files). Press `Enter` to copy the selected entry back to the clipboard, or `Cmd + Backspace` (`Fn + Backspace` on an empty box) to delete it from history.
- **Navigation:** `↑` / `↓` move selection, `Esc` clears the input / exits the current mode / closes the launcher.

## Installation & Running
Once `CCast.dmg` is generated, open it and drag `CCast.app` into your **Applications** folder.

You can then launch CCast directly from Applications or add it to your **Login Items** (*System Settings -> General -> Login Items*) so it starts automatically at boot.
