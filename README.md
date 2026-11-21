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

## Installation & Running
Once `CCast.dmg` is generated, open it and drag `CCast.app` into your **Applications** folder.

You can then launch CCast directly from Applications or add it to your **Login Items** (*System Settings -> General -> Login Items*) so it starts automatically at boot.

Shortcut: press `Option + Space` (`⌥ Space`) to toggle the launcher.
