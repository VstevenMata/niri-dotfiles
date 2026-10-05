// Selector de fondos: carrusel de tarjetas inclinadas, la central grande y las laterales apiladas detrás.
// ←/→, h/l o rueda/touchpad: mover · Enter/clic: aplicar · Esc/clic fuera: cerrar
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: win
    readonly property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string cache: Quickshell.env("HOME") + "/.cache/wallpicker"
    readonly property real skew: 0.33 // inclinación de las tarjetas
    readonly property real cardH: Math.round(height * 0.39) // tarjeta central
    readonly property real cardW: Math.round(cardH * 1.1)
    property string current: ""
    property bool thumbsReady: false
    property bool live: false // sin animación hasta colocarse en el fondo actual

    // target = hacia dónde vamos (real: el touchpad lo mueve en fracciones); pos lo persigue suavemente
    property real target: 0
    property real pos: target
    Behavior on pos { enabled: win.live; SmoothedAnimation { duration: 280; velocity: -1 } }
    readonly property int index: Math.round(target)

    // Abre en el monitor enfocado (lo pasa el bind de niri en WP_OUTPUT)
    screen: Quickshell.screens.find(s => s.name === Quickshell.env("WP_OUTPUT")) ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "wallpicker"

    readonly property int gap: 5 // px entre tarjetas

    // Tamaño relativo según la distancia al centro, medido de la referencia:
    // la central resalta con un salto fuerte (alto 1 → .67, ancho 1 → .41) y las demás se van al fondo:
    // alto .54, .49, .47…  ancho .27, .15, .13… → laterales delgadas y lejanas
    function heightAt(u) { return 0.45 + 0.55 * Math.exp(-0.9 * u) }
    function widthAt(u) { return 0.12 + 0.88 * Math.exp(-1.1 * u) }
    // Distancia del centro de pantalla al centro de la tarjeta a distancia u: suma de medios anchos + gaps.
    // Exacta en posiciones enteras (tarjetas pegadas a 5 px); entre medias interpola.
    function offsetAt(u) {
        const w = t => cardW * widthAt(t)
        const n = Math.floor(u)
        let x = 0
        for (let k = 0; k < n; k++) x += (w(k) + w(k + 1)) / 2 + gap
        return x + (u - n) * ((w(n) + w(n + 1)) / 2 + gap)
    }

    function go(i) { target = Math.max(0, Math.min(folder.count - 1, i)) }
    function apply() {
        Quickshell.execDetached(["dms", "ipc", "call", "wallpaper", "set", folder.get(index, "filePath")])
        Qt.quit()
    }
    function syncCurrent() {
        if (!current || !thumbsReady || folder.status !== FolderListModel.Ready) return
        go(folder.indexOf("file://" + current))
        live = true
    }

    // Arranca centrado en el fondo actual
    Process {
        running: true
        command: ["dms", "ipc", "call", "wallpaper", "get"]
        stdout: StdioCollector { onStreamFinished: { win.current = text.trim(); win.syncCurrent() } }
    }

    // Miniaturas en caché: Qt decodifica en un solo hilo y los .jxl a 4K tardan ~0.7 s cada uno
    Process {
        running: true
        command: [Qt.resolvedUrl("thumbs.sh").toString().slice(7), win.dir, win.cache]
        onExited: { win.thumbsReady = true; win.syncCurrent() }
    }

    FolderListModel {
        id: folder
        folder: "file://" + win.dir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.jxl"]
        showDirs: false
        onStatusChanged: win.syncCurrent()
    }

    Rectangle {
        anchors.fill: parent
        color: "#20000000"
    }

    Item {
        id: stage
        anchors.fill: parent
        focus: true

        // Fondo: clic fuera cierra. Rueda: 1 muesca = 1 tarjeta. Touchpad: sigue al dedo y al soltar encaja.
        MouseArea {
            anchors.fill: parent
            onClicked: Qt.quit()
            onWheel: e => {
                const a = e.angleDelta
                const d = Math.abs(a.x) > Math.abs(a.y) ? a.x : a.y // eje dominante (el touchpad mete ruido en el otro)
                win.go(win.target - d / 120)
                snap.restart()
            }
        }
        Timer { id: snap; interval: 120; onTriggered: win.go(win.index) }

        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) Qt.quit()
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.apply()
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) win.go(win.index - 1)
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) win.go(win.index + 1)
        }

        Repeater {
            model: win.thumbsReady ? folder : null

            delegate: Item {
                id: card
                required property int index
                required property string fileName
                readonly property real d: index - win.pos // distancia continua al centro
                readonly property real u: Math.abs(d)
                // Todo sale de u, así que tamaño y posición cambian a la vez que el scroll (sin saltos)

                visible: u < 11
                z: -u
                width: win.cardW * win.widthAt(u)
                height: win.cardH * win.heightAt(u)
                x: stage.width / 2 + Math.sign(d) * win.offsetAt(u) - width / 2
                y: (stage.height - height) / 2
                clip: true
                // Corta en paralelogramo; la imagen se "des-inclina" para no deformarse
                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -win.skew, 0, win.skew * card.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }

                Image {
                    x: -win.skew * card.height / 2
                    width: card.width + win.skew * card.height
                    height: card.height
                    source: card.visible ? "file://" + win.cache + "/" + card.fileName + ".jpg" : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    transform: Matrix4x4 { matrix: Qt.matrix4x4(1, win.skew, 0, -win.skew * card.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                }
                Rectangle { // más atrás = más oscura, refuerza la profundidad
                    anchors.fill: parent
                    color: "black"
                    opacity: Math.min(0.4, card.u * 0.13)
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: card.index === win.index ? win.apply() : win.go(card.index)
                }
            }
        }
    }
}
