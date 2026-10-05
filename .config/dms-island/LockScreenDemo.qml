pragma ComponentBehavior: Bound

// Reemplazo de Modules/Lock/LockScreenDemo.qml de DMS (lo copia ~/.local/bin/dms-run-custom).
// El "demo" del lock pasa a ser la isla con el sistema desbloqueado, como ventana normal de niri
// (título "Isla"): se mueve entre escritorios como cualquier app. Reglas en ~/.config/niri/custom.kdl.
// Abrir/cerrar: dms ipc call isla toggle   (Super+S; también sirve: dms ipc call lock demo)

import QtQuick
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root

    property bool demoActive: false

    visible: demoActive
    title: "Isla"
    color: "transparent"
    implicitWidth: 1500
    implicitHeight: 860
    minimumSize: Qt.size(1180, 800)

    // cerrada desde niri (Mod+Q): que el próximo toggle la vuelva a abrir
    onVisibleChanged: {
        if (!visible)
            demoActive = false;
    }

    function showDemo(): void {
        demoActive = true;
    }

    function hideDemo(): void {
        demoActive = false;
    }

    IpcHandler {
        target: "isla"

        function toggle(): void {
            root.demoActive = !root.demoActive;
        }
        function open(): void {
            root.showDemo();
        }
        function close(): void {
            root.hideDemo();
        }
    }

    Loader {
        anchors.fill: parent
        active: root.demoActive
        focus: true
        source: "Island.qml"
        onLoaded: {
            item.windowed = true;
            item.screenName = Qt.binding(() => root.screen?.name ?? "");
            item.closeRequested.connect(root.hideDemo);
            item.forceActiveFocus();
        }
    }
}
