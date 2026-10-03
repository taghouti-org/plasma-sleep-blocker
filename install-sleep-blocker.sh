#!/bin/bash
set -e

# Sleep Blocker for KDE Plasma 5
# A panel widget that blocks / allows system sleep. The block is held by a
# root systemd service (systemd-inhibit), not by Plasma, so it survives
# plasmashell crashes and can't be overridden by Plasma's idle/lid handling.

USER_NAME="$(id -un)"
WIDGET_ID="org.taghouti.nosleep"
SRC_DIR="$HOME/.local/src/plasma-nosleep"
BIN_DIR="$HOME/.local/bin"

if ! command -v kpackagetool5 >/dev/null; then
    echo "kpackagetool5 not found: this widget needs KDE Plasma 5." >&2
    exit 1
fi

echo "==> Installing nosleep.service (needs sudo)..."
sudo tee /etc/systemd/system/nosleep.service >/dev/null << 'EOF'
[Unit]
Description=Block system sleep (nosleep switch)

[Service]
# Held by root so the user's own session (Plasma idle timer, lid, Sleep button) can't override it
ExecStart=/usr/bin/systemd-inhibit --what=sleep:idle --mode=block --who=nosleep --why="Sleep blocked by the nosleep switch" /usr/bin/sleep infinity
EOF

echo "==> Allowing $USER_NAME to start/stop it without a password..."
sudo tee /etc/polkit-1/rules.d/20-nosleep.rules >/dev/null << EOF
// Let $USER_NAME start/stop nosleep.service without a password (Plasma widget + nosleep command)
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "nosleep.service" &&
        (action.lookup("verb") == "start" || action.lookup("verb") == "stop") &&
        subject.user == "$USER_NAME" && subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
EOF
sudo systemctl daemon-reload

echo "==> Installing the nosleep command..."
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/nosleep" << 'EOF'
#!/bin/bash
# Block or allow system sleep, independent of Plasma (see /etc/systemd/system/nosleep.service)
case "$1" in
    on)  systemctl start nosleep.service ;;
    off) systemctl stop nosleep.service ;;
    ""|status) ;;
    *) echo "usage: nosleep [on|off|status]" >&2; exit 2 ;;
esac
if systemctl -q is-active nosleep.service; then echo "nosleep: ON (sleep is blocked)"; else echo "nosleep: OFF (sleep allowed)"; fi
EOF
chmod +x "$BIN_DIR/nosleep"

echo "==> Installing the Sleep Blocker widget..."
mkdir -p "$SRC_DIR/contents/ui"
cat > "$SRC_DIR/metadata.json" << 'EOF'
{
    "KPlugin": {
        "Id": "org.taghouti.nosleep",
        "Name": "Sleep Blocker",
        "Description": "Block or allow system sleep. The block is held by a system service, so it survives Plasma crashes.",
        "Icon": "caffeine-cup-full",
        "Authors": [{ "Name": "Tarek" }],
        "Category": "Power Management",
        "License": "GPL",
        "Version": "1.0"
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API": "declarativeappletscript",
    "X-Plasma-MainScript": "ui/main.qml"
}
EOF
cat > "$SRC_DIR/contents/ui/main.qml" << 'EOF'
// Sleep Blocker: toggles /etc/systemd/system/nosleep.service and shows its state.
// The block lives in that service, not here, so a Plasma crash doesn't release it.
import QtQuick 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    property bool blocked: false
    property bool busy: false
    readonly property string checkCmd: "systemctl is-active nosleep.service"

    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation
    Plasmoid.icon: blocked ? "caffeine-cup-full" : "caffeine-cup-empty"
    Plasmoid.toolTipMainText: blocked ? "Sleep blocked" : "Sleep allowed"
    Plasmoid.toolTipSubText: blocked ? "Click to allow sleep again"
                                     : "Click to block sleep (idle, lid and Sleep button)"

    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: {
            if (sourceName === root.checkCmd) {
                root.blocked = data["stdout"].trim() === "active"
            } else {
                root.busy = false
                root.refresh()
            }
            disconnectSource(sourceName)
        }
    }

    function refresh() {
        executable.connectSource(checkCmd)
    }

    function toggle() {
        if (busy) {
            return
        }
        busy = true
        executable.connectSource("systemctl " + (blocked ? "stop" : "start") + " nosleep.service")
    }

    // Also picks up changes made with the nosleep command
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Plasmoid.compactRepresentation: PlasmaCore.IconItem {
        source: Plasmoid.icon
        active: mouseArea.containsMouse
        opacity: root.busy ? 0.5 : 1

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.toggle()
        }
    }
}
EOF
if kpackagetool5 -t Plasma/Applet -s "$WIDGET_ID" >/dev/null 2>&1; then
    kpackagetool5 -t Plasma/Applet -u "$SRC_DIR"
else
    kpackagetool5 -t Plasma/Applet -i "$SRC_DIR"
fi

echo
echo "Done. Add it to a panel: right-click the panel > Add Widgets... > search \"Sleep Blocker\"."
echo "From a terminal: nosleep on | nosleep off | nosleep"
