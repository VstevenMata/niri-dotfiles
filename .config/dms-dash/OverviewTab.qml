import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Modules.DankDash.Overview
import qs.Widgets

// Resumen de DankDash rediseñado (lo copia ~/.local/bin/dms-run-custom sobre el original).
// Arriba: portada con el fondo de pantalla difuminado, hora grande, saludo y clima.
// Abajo: calendario a la izquierda; música y sistema a la derecha.
Item {
    id: root

    implicitWidth: 720
    implicitHeight: 474
    property bool live: Window.window?.visible ?? false

    signal switchToWeatherTab
    signal switchToMediaTab
    signal closeDash
    signal navFocusRequested

    function handleKeyEvent(event) {
        return calendarLoader.item ? calendarLoader.item.handleKeyEvent(event) : false;
    }

    property date now: new Date()
    Timer { interval: 1000; running: root.live; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    readonly property string greeting: now.getHours() < 12 ? "Buenos días" : now.getHours() < 19 ? "Buenas tardes" : "Buenas noches"
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property int gap: 12
    property string mode: "mac"
    property real zenSince: 0
    FileView { path: Quickshell.env("HOME") + "/.local/state/theme-mode"; watchChanges: true; onFileChanged: reload(); onLoaded: root.mode = text().trim() }
    FileView { path: Quickshell.env("HOME") + "/.local/state/theme-zen-since"; watchChanges: true; onFileChanged: reload(); onLoaded: root.zenSince = parseFloat(text()) || 0 }
    readonly property bool zen: mode === "zen"
    readonly property color accent: zen ? "#E3DAC9" : Theme.primary   // hueso en zen
    // Una frase tranquila por día
    readonly property var phrases: [
        "Respira. Un paso a la vez.", "Lo importante primero, lo demás espera.", "Haz una cosa, y hazla bien.",
        "La calma también es avanzar.", "Menos ruido, más claridad.", "Termina lo que empezaste, sin prisa.",
        "Hoy basta con hacerlo un poco mejor.", "El foco es elegir qué ignorar.", "Despacio se llega lejos.",
        "Ordena el espacio, se ordena la mente.", "Pausa, mira lejos, vuelve.", "Cada día es una hoja nueva."
    ]
    readonly property string phrase: phrases[Math.floor(now.getTime() / 86400000) % phrases.length]
    function zenElapsed() {
        const e = Math.max(0, Math.floor(now.getTime() / 1000 - zenSince));
        return Math.floor(e / 3600) + ":" + String(Math.floor(e / 60) % 60).padStart(2, "0");
    }

    // Referencias para que los servicios actualicen solo con el panel abierto
    property bool refs: false
    function syncRefs(w) {
        if (w === refs) return;
        refs = w;
        if (w) { WeatherService.addRef(); DgopService.addRef(["cpu", "memory", "system"]); }
        else { WeatherService.removeRef(); DgopService.removeRef(["cpu", "memory", "system"]); }
    }
    onLiveChanged: syncRefs(live)
    Component.onCompleted: syncRefs(live)
    Component.onDestruction: syncRefs(false)

    component Panel: Rectangle {
        radius: 26
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.55)
        border.width: 1
        border.color: Theme.withAlpha(Theme.surfaceText, 0.06)
    }

    // ---------- Portada ----------
    Item {
        id: hero
        width: parent.width
        height: 140

        Rectangle { id: heroMask; anchors.fill: parent; radius: 28; visible: false; layer.enabled: true }
        Item {
            id: heroBg
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Image {
                anchors.fill: parent
                source: SessionData.wallpaperPath ? "file://" + SessionData.wallpaperPath : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 900
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.25) }
                }
            }
        }
        MultiEffect { anchors.fill: parent; source: heroBg; blurEnabled: true; blur: 0.6; blurMax: 48; maskEnabled: true; maskSource: heroMask }
        Rectangle { anchors.fill: parent; radius: 28; color: "transparent"; border.width: 1; border.color: Theme.withAlpha(Theme.surfaceText, 0.08) }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                StyledText {
                    text: root.greeting + ", " + (UserInfoService.fullName.split(" ")[0] || UserInfoService.username)
                    font.pixelSize: 13; font.letterSpacing: 0.5
                    color: "white"; opacity: 0.7
                }
                Row {
                    spacing: 6
                    StyledText {
                        text: Qt.formatTime(root.now, "hh:mm")
                        font.pixelSize: 64; font.weight: Font.Light
                        font.features: { "tnum": 1 }
                        color: "white"
                    }
                    StyledText {
                        anchors.baseline: parent.children[0].baseline
                        text: Qt.formatTime(root.now, "ss")
                        font.pixelSize: 18; font.weight: Font.Light
                        font.features: { "tnum": 1 }
                        color: "white"; opacity: 0.45
                    }
                }
                StyledText {
                    text: { const s = Qt.locale("es_ES").toString(root.now, "dddd, d 'de' MMMM"); return s.charAt(0).toUpperCase() + s.slice(1) + (root.zen ? "   ·   " + root.zenElapsed() + " en zen" : "") }
                    font.pixelSize: 14
                    color: "white"; opacity: 0.75
                }
                StyledText {
                    topPadding: 6
                    text: "“" + root.phrase + "”"
                    font.pixelSize: 12; font.italic: true
                    color: "white"; opacity: 0.5
                }
            }
        }

        // Clima (clic: pestaña de clima)
        MouseArea {
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            width: wRow.width; height: wRow.height
            visible: SettingsData.weatherEnabled && WeatherService.weather.available
            cursorShape: Qt.PointingHandCursor
            onClicked: root.switchToWeatherTab()
            Row {
                id: wRow
                spacing: 12
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: WeatherService.getWeatherIcon(WeatherService.weather.wCode)
                    size: 40; color: "white"; opacity: 0.9
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    StyledText { text: WeatherService.currentTempText(false); font.pixelSize: 30; font.weight: Font.Light; color: "white" }
                    StyledText { text: WeatherService.getWeatherCondition(WeatherService.weather.wCode); font.pixelSize: 12; color: "white"; opacity: 0.65 }
                }
            }
        }
    }

    // ---------- Accesos rápidos ----------
    component Chip: Rectangle {
        id: chip
        property string icon
        property string label
        property bool active: false
        property var action
        height: 40
        radius: 20
        width: (parent.width - root.gap * 4) / 5
        color: active ? Theme.withAlpha(root.accent, 0.18) : (cma.containsMouse ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.9) : Theme.withAlpha(Theme.surfaceContainerHigh, 0.55))
        border.width: 1
        border.color: active ? Theme.withAlpha(root.accent, 0.5) : Theme.withAlpha(Theme.surfaceText, 0.06)
        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
        Row {
            anchors.centerIn: parent
            spacing: 7
            DankIcon { anchors.verticalCenter: parent.verticalCenter; name: chip.icon; size: 17; color: chip.active ? root.accent : Theme.surfaceText; opacity: chip.active ? 1 : 0.6 }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: chip.label; font.pixelSize: 12; font.weight: Font.Medium; color: Theme.surfaceText; opacity: chip.active ? 1 : 0.65 }
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.action() }
    }

    Row {
        id: chips
        y: hero.height + root.gap
        width: parent.width
        spacing: root.gap
        Chip { icon: SessionData.doNotDisturb ? "notifications_off" : "notifications"; label: "No molestar"; active: SessionData.doNotDisturb
            action: () => Quickshell.execDetached(["dms", "ipc", "call", "notifications", SessionData.doNotDisturb ? "disableDoNotDisturb" : "enableDoNotDisturbIndefinitely"]) }
        Chip { icon: "nightlight"; label: "Luz cálida"; active: DisplayService.nightModeEnabled; action: () => DisplayService.toggleNightMode() }
        Chip { icon: "coffee"; label: "Despierto"; active: SessionService.idleInhibited; action: () => SessionService.toggleIdleInhibit() }
        Chip { icon: "screenshot_region"; label: "Captura"; action: () => { root.closeDash(); Quickshell.execDetached(["dms", "ipc", "call", "niri", "screenshot"]) } }
    }

    // ---------- Calendario ----------
    Loader {
        id: calendarLoader
        x: 0
        y: chips.y + chips.height + root.gap
        width: Math.round(parent.width * 0.56)
        height: parent.height - y
        asynchronous: true
        sourceComponent: Component {
            CalendarOverviewCard {
                radius: 26
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.55)
                border.color: Theme.withAlpha(Theme.surfaceText, 0.06)
                onCloseDash: root.closeDash()
                onNavFocusRequested: root.navFocusRequested()
            }
        }
        DankSpinner { anchors.centerIn: parent; size: 32; visible: calendarLoader.status === Loader.Loading }
    }

    // ---------- Música ----------
    Panel {
        id: media
        x: calendarLoader.width + root.gap
        y: chips.y + chips.height + root.gap
        width: parent.width - x
        height: 136

        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.switchToMediaTab() }

        Column {
            anchors.centerIn: parent
            visible: !root.player
            spacing: 6
            DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "music_off"; size: 28; color: Theme.surfaceText; opacity: 0.35 }
            StyledText { text: "Nada sonando"; font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.45 }
        }

        Item {
            anchors.fill: parent
            anchors.margins: 16
            visible: !!root.player

            Rectangle {
                id: artBox
                width: 64; height: 64; radius: 14
                color: Theme.withAlpha(Theme.surfaceText, 0.06)
                Image { id: art; anchors.fill: parent; source: root.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: false }
                Rectangle { id: artMask; anchors.fill: parent; radius: 14; visible: false; layer.enabled: true }
                MultiEffect { anchors.fill: art; source: art; maskEnabled: true; maskSource: artMask; visible: art.status === Image.Ready }
                DankIcon { anchors.centerIn: parent; visible: art.status !== Image.Ready; name: "music_note"; size: 26; color: Theme.surfaceText; opacity: 0.35 }
            }
            Column {
                anchors.left: artBox.right; anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: artBox.verticalCenter
                spacing: 2
                StyledText { width: parent.width; elide: Text.ElideRight; wrapMode: Text.NoWrap; maximumLineCount: 1; text: root.player?.trackTitle || "Sin título"; font.pixelSize: 14; font.weight: Font.Medium; color: Theme.surfaceText }
                StyledText { width: parent.width; elide: Text.ElideRight; wrapMode: Text.NoWrap; maximumLineCount: 1; text: root.player?.trackArtist || root.player?.identity || ""; font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.55 }
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 26
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "skip_previous"; size: 22; color: Theme.surfaceText; opacity: pv.containsMouse ? 1 : 0.6
                    MouseArea { id: pv; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.player.previous() }
                }
                Rectangle {
                    width: 40; height: 40; radius: 20
                    color: Theme.surfaceText
                    DankIcon { anchors.centerIn: parent; name: root.player?.isPlaying ? "pause" : "play_arrow"; size: 22; color: Theme.surface }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.player.togglePlaying() }
                }
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "skip_next"; size: 22; color: Theme.surfaceText; opacity: nx.containsMouse ? 1 : 0.6
                    MouseArea { id: nx; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.player.next() }
                }
            }
        }
    }

    // ---------- Sistema ----------
    Panel {
        x: media.x
        y: media.y + media.height + root.gap
        width: media.width
        height: parent.height - y

        component Meter: Column {
            property string icon
            property string label
            property real value
            property string text
            width: parent.width
            spacing: 6
            Item {
                width: parent.width; height: 16
                Row {
                    spacing: 6
                    DankIcon { name: icon; size: 15; color: Theme.surfaceText; opacity: 0.6; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { text: label; font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.6; anchors.verticalCenter: parent.verticalCenter }
                }
                StyledText { anchors.right: parent.right; text: parent.parent.text; font.pixelSize: 12; font.features: { "tnum": 1 }; color: Theme.surfaceText; opacity: 0.85 }
            }
            Rectangle {
                width: parent.width; height: 4; radius: 2
                color: Theme.withAlpha(Theme.surfaceText, 0.08)
                Rectangle {
                    height: parent.height; radius: 2
                    width: parent.width * Math.max(0.02, Math.min(1, value))
                    color: value > 0.85 ? Theme.error : root.accent
                    opacity: 0.8
                }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 9
            Meter { icon: "memory"; label: "CPU"; value: DgopService.cpuUsage / 100; text: Math.round(DgopService.cpuUsage) + "%" }
            Meter { icon: "developer_board"; label: "Memoria"; value: DgopService.memoryUsage / 100; text: (DgopService.usedMemoryMB / 1024).toFixed(1) + " / " + (DgopService.totalMemoryMB / 1024).toFixed(0) + " GB" }
            Meter { icon: "device_thermostat"; label: "Temperatura"; value: DgopService.cpuTemperature / 100; text: Math.round(DgopService.cpuTemperature) + "°C" }
        }
    }
}
