import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Indicadores temporales en el centro de la barra (reemplazan los avisos flotantes de DMS):
// volumen y silencio, micrófono y brillo. Aparecen al cambiar y se van 1.2 s después del último
// cambio. El nivel se dibuja en modo ondas: una línea que ondula hasta el nivel y fluye.
// Sobre la pastilla, la rueda del mouse ajusta lo que se está mostrando.
PluginComponent {
    id: root

    readonly property var spk: AudioService.sink?.audio ?? null
    readonly property var mic: AudioService.source?.audio ?? null
    readonly property var dev: DisplayService.getCurrentDeviceInfo()

    property string kind: "vol"     // vol | mic | bright
    property bool shown: false
    property bool ready: false

    readonly property int value: {
        if (kind === "vol") return spk ? Math.round(spk.volume * 100) : 0;
        if (kind === "mic") return mic ? Math.round(mic.volume * 100) : 0;
        const lo = DisplayService.brightnessMinimum(dev), hi = DisplayService.brightnessMaximum(dev);
        return Math.round(100 * (DisplayService.brightnessLevel - lo) / Math.max(1, hi - lo));
    }
    readonly property bool off: kind === "vol" ? (spk?.muted ?? false) : kind === "mic" ? (mic?.muted ?? false) : false
    readonly property string label: kind === "vol" ? "Volumen" : kind === "mic" ? "Micrófono" : "Brillo"
    readonly property string icon: {
        if (kind === "mic") return off ? "mic_off" : "mic";
        if (kind === "bright") return value < 35 ? "brightness_low" : value < 70 ? "brightness_medium" : "brightness_high";
        return off || value === 0 ? "volume_off" : value < 40 ? "volume_down" : "volume_up";
    }

    function flash(k) {
        if (!ready) return;
        kind = k;
        shown = true;
        hideTimer.restart();
        if (k !== "mic") chime();
    }

    // Nota suave cuya altura sigue el nivel (escala pentatónica, ~/.config/dms-sounds/tono-0..6.wav).
    // Reemplaza el sonido de volumen de DMS (soundVolumeChanged=false). Máximo una cada 120 ms.
    property real lastChime: 0
    function chime() {
        const t = Date.now();
        if (off || t - lastChime < 120) return;
        lastChime = t;
        const i = Math.max(0, Math.min(6, Math.round(value / 100 * 6)));
        Quickshell.execDetached(["pw-play", "--volume", "0.4", Quickshell.env("HOME") + "/.config/dms-sounds/tono-" + i + ".wav"]);
    }
    Timer { id: hideTimer; interval: 1200; onTriggered: root.shown = false }
    Timer { interval: 2000; running: true; onTriggered: root.ready = true }   // no aparecer al arrancar

    Connections {
        target: root.spk
        function onVolumeChanged() { root.flash("vol") }
        function onMutedChanged() { root.flash("vol") }
    }
    Connections {
        target: root.mic
        function onVolumeChanged() { root.flash("mic") }
        function onMutedChanged() { root.flash("mic") }
    }
    Connections {
        target: DisplayService
        function onBrightnessChanged(showOsd) { if (showOsd) root.flash("bright") }
    }

    onShownChanged: shown ? clearVisibilityOverride() : setVisibilityOverride(false)
    Component.onCompleted: setVisibilityOverride(false)

    function nudge(up) {
        const v = Math.max(0, Math.min(100, value + (up ? 5 : -5)));
        if (kind === "vol") AudioService.setVolume(v);
        else if (kind === "mic" && mic) mic.volume = v / 100;
        else DisplayService.setBrightness(Math.round(DisplayService.brightnessMinimum(dev) + v / 100 * (DisplayService.brightnessMaximum(dev) - DisplayService.brightnessMinimum(dev))), "", true);
    }

    horizontalBarPill: Component {
        Row {
            spacing: 10
            WheelHandler { onWheel: ev => root.nudge(ev.angleDelta.y > 0) }

            DankIcon { anchors.verticalCenter: parent.verticalCenter; name: root.icon; size: 16; color: Theme.surfaceText; opacity: root.off ? 0.45 : 0.85 }

            // Modo ondas: la línea ondula hasta el nivel y sigue plana después; fluye mientras se ve
            Canvas {
                id: wave
                anchors.verticalCenter: parent.verticalCenter
                width: 104; height: 18
                property real level: root.off ? 0 : Math.min(1, root.value / 100)
                property real shownLevel: level
                property real phase: 0
                Behavior on shownLevel { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                onShownLevelChanged: requestPaint()
                onPhaseChanged: requestPaint()
                Timer { interval: 33; running: root.shown && !root.off; repeat: true; onTriggered: wave.phase += 0.22 }
                onPaint: {
                    const c = getContext("2d"), w = width, mid = height / 2, col = Theme.surfaceText;
                    const cut = w * shownLevel;
                    c.reset();
                    c.lineCap = "round";
                    // resto plano y tenue
                    c.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.14);
                    c.lineWidth = 1.5;
                    c.beginPath(); c.moveTo(Math.max(1, cut), mid); c.lineTo(w - 1, mid); c.stroke();
                    if (cut < 2) return;
                    // tramo ondulado: más amplitud cuanto más alto el nivel, suavizado en los extremos
                    const g = c.createLinearGradient(0, 0, cut, 0);
                    g.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0.45));
                    g.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0.95));
                    c.strokeStyle = g;
                    c.lineWidth = 2;
                    const A = 1.5 + 4.5 * shownLevel;
                    c.beginPath();
                    for (let x = 1; x <= cut; x += 1.5) {
                        const env = Math.sin(Math.PI * Math.min(1, x / cut));
                        const y = mid + A * env * Math.sin(x * 0.28 - wave.phase);
                        x === 1 ? c.moveTo(x, y) : c.lineTo(x, y);
                    }
                    c.stroke();
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText; opacity: 0.55
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(implicitWidth, 40)
                text: root.off ? "silencio" : root.value + "%"
                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; font.features: { "tnum": 1 }
                color: Theme.surfaceText; opacity: root.off ? 0.5 : 0.9
            }
        }
    }

    // En los bordes laterales: icono y nivel; la rueda sigue ajustando
    verticalBarPill: Component {
        Column {
            spacing: 3
            WheelHandler { onWheel: ev => root.nudge(ev.angleDelta.y > 0) }
            DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: root.icon; size: 16; color: Theme.surfaceText; opacity: root.off ? 0.45 : 0.85 }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.off ? "—" : root.value
                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; font.features: { "tnum": 1 }
                color: Theme.surfaceText; opacity: root.off ? 0.5 : 0.9
            }
        }
    }
}
