import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Mientras arrastras un widget o una píldora: la copia va pegada al cursor y se resalta dónde caerá
// (contorno de la píldora destino + barra en el hueco, o la silueta exacta de la píldora nueva).
// No recibe clics.
PanelWindow {
    id: win

    readonly property var hint: FloatingPillService.hint
    readonly property color accent: Theme.primary

    color: "transparent"
    WlrLayershell.namespace: "dms:pill-drag"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    mask: Region {}

    // La copia, centrada en el cursor, como una mini píldora
    Rectangle {
        readonly property size s: FloatingPillService.dragSize
        visible: FloatingPillService.dragImage != ""
        opacity: 0.75
        width: s.width + 16
        height: s.height + 8
        x: FloatingPillService.dragPos.x - width / 2
        y: FloatingPillService.dragPos.y - height / 2
        radius: Math.min(width, height) / 2
        color: Theme.withAlpha(Theme.surfaceContainer, 0.95)
        border.width: 1
        border.color: Theme.withAlpha(win.accent, 0.6)

        Image {
            anchors.centerIn: parent
            source: FloatingPillService.dragImage
            width: parent.s.width
            height: parent.s.height
        }
    }

    // Encima de la copia, para que siempre se vea dónde cae:
    // píldora destino
    Rectangle {
        readonly property var t: win.hint?.target ?? null
        visible: t !== null
        x: t?.x ?? 0
        y: t?.y ?? 0
        width: t?.w ?? 0
        height: t?.h ?? 0
        radius: Math.min(width, height) / 2
        color: Theme.withAlpha(win.accent, 0.12)
        border.width: 2
        border.color: win.accent
    }

    // hueco donde entra el widget
    Rectangle {
        visible: win.hint?.kind === "insert"
        x: win.hint?.x ?? 0
        y: win.hint?.y ?? 0
        width: win.hint?.w ?? 0
        height: win.hint?.h ?? 0
        radius: 2
        color: win.accent
    }

    // píldora nueva: silueta exacta donde quedará (en rojo si pisa otra: ahí no se puede soltar)
    Rectangle {
        readonly property color c: win.hint?.kind === "blocked" ? Theme.error : win.accent
        visible: win.hint?.kind === "new" || win.hint?.kind === "blocked"
        x: win.hint?.x ?? 0
        y: win.hint?.y ?? 0
        width: win.hint?.w ?? 0
        height: win.hint?.h ?? 0
        radius: Math.min(width, height) / 2
        color: Theme.withAlpha(c, 0.18)
        border.width: 2
        border.color: c
    }
}
