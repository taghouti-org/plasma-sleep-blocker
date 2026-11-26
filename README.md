# Sleep Blocker for KDE Plasma 5 & 6

A panel widget that blocks or allows system sleep with one click, and shows whether sleep is currently blocked.

## Problem

Plasma's built-in "Manually block sleep and screen locking" option (in the battery widget) is held by the `plasmashell` process. If Plasma crashes or restarts, the block is silently released and comes back **off**, so the laptop goes to sleep on the idle timer even though you turned the block on.

## Solution

The block is moved out of Plasma into a tiny root systemd service:

- **`nosleep.service`** runs `systemd-inhibit --what=sleep:idle --mode=block`. It keeps running if Plasma crashes, and because it's held by root, your own session (Plasma's idle timer, closing the lid, the Sleep button) can't override it.
- **Sleep Blocker widget** is only a switch: it starts/stops the service and shows its state.
- **`nosleep` command** does the same from a terminal.
- A narrow polkit rule lets your user start/stop **only this service** without a password.

## Quick Install

```bash
curl -L https://raw.githubusercontent.com/taghouti-org/plasma-sleep-blocker/main/install-sleep-blocker.sh | bash
```

It asks for your password once (sudo) to install the service and the polkit rule. Then add the widget: right-click the panel → **Add Widgets…** → search **"Sleep Blocker"**.

## Usage

| Icon | Meaning | Click |
|------|---------|-------|
| ☕ full cup | Sleep is blocked | Allow sleep again |
| empty cup | Sleep is allowed | Block sleep |

Hover the icon for the current status.

### Terminal

```bash
nosleep on       # block sleep
nosleep off      # allow sleep
nosleep          # show status
systemd-inhibit --list   # the block shows up as "nosleep"
```

The widget picks up changes made from the terminal within 5 seconds.

The block is **off after a reboot**, so the machine never stays awake by accident. To keep it across reboots, add an `[Install]` section with `WantedBy=multi-user.target` to the service and `sudo systemctl enable nosleep.service`.

## Requirements

- KDE Plasma 6 (tested on Plasma 6.6, Kubuntu 26.04) or Plasma 5 (tested on Plasma 5.27, Kubuntu 24.04). The installer detects which one you have.
- systemd and polkit
- An icon theme with `caffeine-cup-full` / `caffeine-cup-empty` (Papirus, Breeze and most popular themes have them)

## What gets installed

| File | Purpose |
|------|---------|
| `/etc/systemd/system/nosleep.service` | Holds the sleep block (not enabled at boot) |
| `/etc/polkit-1/rules.d/20-nosleep.rules` | Lets your user start/stop only `nosleep.service` without a password |
| `~/.local/bin/nosleep` | Terminal command |
| `~/.local/src/plasma-nosleep/` | Widget source |
| `~/.local/share/plasma/plasmoids/org.taghouti.nosleep/` | Installed widget |

## Uninstall

```bash
nosleep off
kpackagetool6 -t Plasma/Applet -r org.taghouti.nosleep   # kpackagetool5 on Plasma 5
sudo rm /etc/systemd/system/nosleep.service /etc/polkit-1/rules.d/20-nosleep.rules
sudo systemctl daemon-reload
rm -rf ~/.local/bin/nosleep ~/.local/src/plasma-nosleep
```

Remove the widget from the panel first if it's there.

## How it works

1. Clicking the widget runs `systemctl start|stop nosleep.service`; the polkit rule approves it without a password for your active local session.
2. The service runs `systemd-inhibit` as root with a `sleep:idle` block lock. logind refuses suspend/hibernate requests from your session while a block lock from another user (root) exists, so Plasma's idle timer, lid action and Sleep button can't put the machine to sleep.
3. The widget polls `systemctl is-active nosleep.service` every 5 seconds to show the real state, so it's correct again right after a Plasma restart.
