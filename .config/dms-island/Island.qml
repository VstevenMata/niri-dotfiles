pragma ComponentBehavior: Bound

// La isla: mismo diseño bloqueado (con contraseña, dentro del WlSessionLock de DMS)
// y desbloqueado (dashboard en capa overlay). La autenticación es la de DMS (Pam.qml);
// aquí solo se escribe la contraseña y se llama a pam.passwd.start().

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

FocusScope {
    id: root

    property bool locked: false
    property bool windowed: false // true: dentro de una ventana normal de niri (Super+S)
    property var pam: null
    property var sessionLock: null
    property string screenName: ""

    signal passwordEdited(string text)
    signal closeRequested

    // Paleta del fondo de pantalla (colores dinámicos de DMS, cambian con el wallpaper); ember solo para errores y carga alta
    readonly property color ink: Theme.surface
    readonly property color tide: Theme.primaryContainer
    readonly property color fog: Theme.surfaceVariantText
    readonly property color mist: Theme.blend(Theme.surfaceText, Theme.primary, 0.45)
    readonly property color moon: Theme.surfaceText
    readonly property color ember: Theme.error
    readonly property var swatches: [Theme.surface, Theme.surfaceContainer, Theme.primaryContainer, Theme.tertiary, Theme.secondary, Theme.primary, Theme.surfaceVariantText, Theme.surfaceText]
    readonly property string display: "Antonio"
    readonly property string sans: "Inter Variable"
    readonly property string mono: "JetBrainsMono Nerd Font Mono"

    property bool unlocking: false
    property string pamState: ""
    property bool readySent: false
    property var fetch: []
    property var disk: null // bytes de "/" según fastfetch: used, available, total
    property real home: -1 // bytes de la carpeta personal (du); -1 mientras calcula

    readonly property string wallpaper: {
        const w = SessionData.getMonitorWallpaper(screenName) || SettingsData.lockScreenWallpaperPath;
        return w && !w.startsWith("#") ? "file://" + w.split("/").map(s => encodeURIComponent(s)).join("/") : "";
    }

    function reset() {
        unlocking = false;
        pamState = "";
        readySent = false;
        passwordField.text = "";
        if (pam)
            pam.lockMessage = "";
        passwordField.forceActiveFocus();
    }

    function submit() {
        if (locked && pam && !unlocking && !pam.passwd.active && !pam.u2fPending)
            pam.passwd.start();
    }

    // DMS suelta el inhibidor de suspensión cuando el lock ya se ve (misma regla que LockScreenContent:
    // solo con secure=true, así el escritorio nunca queda a la vista al suspender)
    function maybeSendReady() {
        if (!locked || readySent || unlocking || !sessionLock || !sessionLock.secure)
            return;
        readySent = true;
        if (SessionService.loginctlAvailable && DMSService.apiVersion >= 2)
            DMSService.sendRequest("loginctl.lockerReady", null, () => {});
    }

    function feedback() {
        if (!pam)
            return "";
        if (unlocking)
            return "Desbloqueando…";
        if (pam.lockMessage)
            return pam.lockMessage;
        if (pamState === "fail")
            return "Contraseña incorrecta";
        if (pamState === "max")
            return "Demasiados intentos, espera un momento";
        if (pamState === "error")
            return "No se pudo verificar, intenta otra vez";
        if (pam.fprintState === "fail")
            return "Huella no reconocida";
        if (pam.u2fState === "waiting" || pam.u2fState === "insert")
            return "Toca tu llave de seguridad";
        if (pam.passwd.active)
            return "Verificando…";
        return "";
    }

    function gib(bytes) {
        return (bytes / 1073741824).toFixed(1);
    }
    // GB "normales" (1000³), como los que anuncia el fabricante del disco
    function gb(bytes) {
        return (bytes / 1e9).toFixed(1);
    }

    function parseFetch(json) {
        const out = [];
        let data;
        try {
            data = JSON.parse(json);
        } catch (e) {
            return;
        }
        for (const m of data) {
            const r = m.result;
            if (!r)
                continue;
            switch (m.type) {
            case "OS":
                out.push(["OS", r.versionID ? r.name + " " + r.versionID : r.prettyName]);
                break;
            case "Kernel":
                out.push(["KERNEL", r.release.replace(/\.x86_64$/, "")]);
                break;
            case "WM":
                out.push(["WM", r.prettyName + (r.version ? " " + r.version : "")]);
                break;
            case "Packages":
                out.push(["PKGS", r.all + (r.flatpakSystem || r.flatpakUser ? " · " + ((r.flatpakSystem || 0) + (r.flatpakUser || 0)) + " flatpak" : "")]);
                break;
            case "CPU":
                out.push(["CPU", r.cpu.replace(/\((R|TM)\)/g, "").replace(/\d+th Gen /, "").replace(/Intel |Core |AMD |Ryzen /g, "").trim() + " · " + r.cores.logical + "t"]);
                break;
            case "GPU":
                if (r.length)
                    out.push(["GPU", (r[0].vendor ? r[0].vendor + " " : "") + r[0].name]);
                break;
            case "Memory":
                out.push(["MEM", gib(r.used) + " / " + gib(r.total) + " GiB"]);
                break;
            case "Disk":
                if (r.length)
                    disk = r[0].bytes;
                if (r.length)
                    out.push(["DISK", Math.round(r[0].bytes.used / 1e9) + " / " + Math.round(r[0].bytes.total / 1e9) + " GB"]);
                break;
            }
        }
        fetch = out;
    }

    Component.onCompleted: {
        DgopService.addRef(["cpu", "memory", "system"]);
        WeatherService.addRef();
        reset();
    }
    Component.onDestruction: {
        DgopService.removeRef(["cpu", "memory", "system"]);
        WeatherService.removeRef();
    }

    Process {
        running: true
        command: ["fastfetch", "--format", "json", "-s", "OS:Kernel:WM:Packages:CPU:GPU:Memory:Disk"]
        stdout: StdioCollector {
            onStreamFinished: root.parseFetch(text)
        }
    }

    // Tamaño de la carpeta personal; tarda unos segundos, por eso va aparte
    Process {
        running: true
        command: ["du", "-sxb", Quickshell.env("HOME")]
        stdout: StdioCollector {
            onStreamFinished: root.home = parseInt(text) || 0
        }
    }

    Connections {
        target: root.pam
        enabled: root.locked && target !== null
        function onUnlockRequested() {
            root.unlocking = true;
            passwordField.text = "";
        }
        function onStateChanged() {
            root.pamState = root.pam.state;
            if (root.pam.state === "")
                return;
            root.unlocking = false;
            passwordField.text = "";
            stateClear.restart();
        }
        function onUnlockInProgressChanged() {
            if (!root.pam.unlockInProgress)
                root.unlocking = false;
        }
    }
    Connections {
        target: root.sessionLock
        enabled: target !== null
        function onSecureChanged() {
            root.maybeSendReady();
        }
    }
    Connections {
        target: root.Window.window
        enabled: root.locked && target !== null
        function onAfterRendering() {
            root.maybeSendReady();
        }
    }
    Timer {
        id: stateClear
        interval: 4000
        onTriggered: root.pamState = ""
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ── Fondo: el wallpaper desenfocado y oscurecido; tapa todo el escritorio (no en modo ventana)
    Rectangle {
        anchors.fill: parent
        visible: !root.windowed
        color: root.ink
    }
    Image {
        anchors.fill: parent
        source: root.wallpaper
        sourceSize: Qt.size(960, 600)
        fillMode: Image.PreserveAspectCrop
        visible: !root.windowed && root.wallpaper !== ""
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: -0.2
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: !root.windowed
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.rgba(0, 0, 0, 0.35)
            }
            GradientStop {
                position: 1
                color: Qt.rgba(0, 0, 0, 0.6)
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: !root.locked && !root.windowed
        onClicked: root.closeRequested()
    }

    Keys.onEscapePressed: {
        if (!root.locked)
            root.closeRequested();
    }

    // ── Piezas ─────────────────────────────────────────────────────────
    component Label: Text {
        font.family: root.mono
        font.pixelSize: 10
        font.letterSpacing: 2
        color: root.fog
    }
    component Body: Text {
        font.family: root.sans
        font.pixelSize: 14
        color: root.mist
        elide: Text.ElideRight
    }
    component Card: Rectangle {
        radius: 24
        color: Qt.rgba(1, 1, 1, 0.035)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
    }
    component CardTitle: RowLayout {
        property string icon
        property string title
        property string aside
        spacing: 8
        DankIcon {
            name: parent.icon
            size: 16
            color: root.fog
        }
        Body {
            text: parent.title
            font.pixelSize: 13
            font.weight: Font.Medium
            Layout.fillWidth: true
        }
        Label {
            text: parent.aside
            font.letterSpacing: 0.5
        }
    }
    // Imagen con esquinas redondeadas (o círculo con radius = width / 2)
    component Rounded: Item {
        property alias source: img.source
        property real radius: 14
        readonly property int status: img.status
        Image {
            id: img
            anchors.fill: parent
            sourceSize: Qt.size(parent.width * 2, parent.height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: roundMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
        Rectangle {
            id: roundMask
            anchors.fill: parent
            radius: parent.radius
            visible: false
            layer.enabled: true
        }
    }
    // Anillo de 270° con el hueco abajo; el valor brilla un poco
    component Gauge: Item {
        id: gauge
        property real value: 0
        property string text
        property string label
        property string icon: ""
        property color tint: value >= 85 ? root.ember : root.mist
        readonly property real s: Math.min(width, height)
        implicitWidth: 104
        implicitHeight: 104

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.12)
                strokeWidth: 6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: gauge.width / 2
                    centerY: gauge.height / 2
                    radiusX: gauge.s / 2 - 7
                    radiusY: gauge.s / 2 - 7
                    startAngle: 135
                    sweepAngle: 270
                }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: true
            layer.samples: 4
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: gauge.tint
                shadowBlur: 0.6
                shadowOpacity: 0.55
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }
            ShapePath {
                strokeColor: gauge.tint
                strokeWidth: 6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: gauge.width / 2
                    centerY: gauge.height / 2
                    radiusX: gauge.s / 2 - 7
                    radiusY: gauge.s / 2 - 7
                    startAngle: 135
                    sweepAngle: Math.max(1, 270 * Math.min(100, gauge.value) / 100)
                }
            }
        }
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -4
            text: gauge.text
            font.family: root.display
            font.pixelSize: Math.round(gauge.s * 0.29)
            font.weight: Font.Normal
            color: root.moon
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: gauge.s / 2 - 10
            spacing: 3
            DankIcon {
                visible: gauge.icon !== ""
                name: gauge.icon
                size: 11
                color: root.fog
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                text: gauge.label
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    component VolButton: Rectangle {
        id: vb
        property string icon
        property real iconSize: 16
        property bool accent: false
        signal clicked
        implicitWidth: 28
        implicitHeight: 28
        radius: 14
        color: vbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
        scale: vbMouse.pressed ? 0.9 : 1
        Behavior on scale {
            NumberAnimation {
                duration: 90
            }
        }
        DankIcon {
            anchors.centerIn: parent
            name: vb.icon
            size: vb.iconSize
            color: vb.accent ? root.moon : root.mist
        }
        MouseArea {
            id: vbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: vb.clicked()
        }
    }

    component Orbit: Shape {
        id: orbit
        property real from: 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        rotation: -14
        ShapePath {
            strokeColor: Theme.withAlpha(root.moon, 0.55)
            strokeWidth: 1.5
            fillColor: "transparent"
            PathAngleArc {
                centerX: planet.width / 2
                centerY: planet.height / 2
                radiusX: 198
                radiusY: 42
                startAngle: orbit.from
                sweepAngle: 180
            }
        }
    }

    // ── La isla ───────────────────────────────────────────────────────
    Rectangle {
        id: island
        anchors.centerIn: parent
        width: root.windowed ? parent.width : Math.min(parent.width - 80, 1500)
        height: root.windowed ? parent.height : Math.min(parent.height - 80, 860)
        radius: 36
        color: Theme.withAlpha(root.ink, root.windowed ? 0.72 : 0.58)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.09)

        MouseArea {
            anchors.fill: parent // los clicks dentro no cierran el dashboard
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 24

            // ── Izquierda: clima, fastfetch, música ──────────────────
            ColumnLayout {
                Layout.preferredWidth: 380
                Layout.minimumWidth: 330
                Layout.fillHeight: true
                spacing: 16

                Card {
                    id: weatherCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 262
                    readonly property var w: WeatherService.weather
                    readonly property var today: w.forecast && w.forecast.length ? w.forecast[0] : null

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 0
                        visible: weatherCard.w.available

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Text {
                                    text: WeatherService.formatTemp(weatherCard.w.temp)
                                    font.family: root.display
                                    font.pixelSize: 72
                                    font.weight: Font.Light
                                    color: root.moon
                                }
                                Body {
                                    text: WeatherService.getWeatherCondition(weatherCard.w.wCode)
                                    font.pixelSize: 15
                                    Layout.fillWidth: true
                                }
                            }
                            DankIcon {
                                name: WeatherService.getWeatherIcon(weatherCard.w.wCode, weatherCard.w.isDay)
                                size: 64
                                color: root.mist
                                Layout.alignment: Qt.AlignTop
                            }
                        }
                        Label {
                            Layout.topMargin: 8
                            text: "SENSACIÓN " + WeatherService.formatTemp(weatherCard.w.feelsLike) + (weatherCard.today ? "  ·  ↑ " + WeatherService.formatTemp(weatherCard.today.tempMax) + "  ↓ " + WeatherService.formatTemp(weatherCard.today.tempMin) : "")
                            font.letterSpacing: 1
                        }
                        Item {
                            Layout.fillHeight: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Repeater {
                                model: (weatherCard.w.forecast || []).slice(1, 6)
                                Column {
                                    id: day
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: new Date(Date.now() + (day.index + 1) * 86400000).toLocaleDateString(Qt.locale(), "ddd").replace(".", "").toUpperCase()
                                        font.letterSpacing: 1
                                    }
                                    DankIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        name: WeatherService.getWeatherIcon(day.modelData.wCode, true)
                                        size: 20
                                        color: root.mist
                                    }
                                    Body {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: WeatherService.formatTemp(day.modelData.tempMax)
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: !weatherCard.w.available
                        DankIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "cloud_off"
                            size: 36
                            color: root.fog
                        }
                        Body {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: weatherCard.w.loading ? "Cargando el clima…" : "Sin datos del clima"
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "UBICACIÓN EN AJUSTES DE DMS → CLIMA"
                            visible: !weatherCard.w.loading
                            font.letterSpacing: 1
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 18

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                implicitWidth: fetchChip.implicitWidth + 20
                                implicitHeight: 26
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.06)
                                Text {
                                    id: fetchChip
                                    anchors.centerIn: parent
                                    text: "❯ fastfetch"
                                    font.family: root.mono
                                    font.pixelSize: 12
                                    color: root.mist
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Label {
                                text: (UserInfoService.username || Quickshell.env("USER")) + "@" + (DgopService.hostname || "linux")
                                font.letterSpacing: 0.5
                                font.pixelSize: 11
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 20

                            // Logo de Fedora recoloreado con el fondo de pantalla: círculo = acento, "f" = texto sobre acento
                            FileView {
                                id: fedoraSvg
                                path: "/usr/share/pixmaps/fedora-logo-sprite.svg"
                                blockLoading: true
                            }
                            Image {
                                source: "data:image/svg+xml;utf8," + encodeURIComponent(fedoraSvg.text()
                                    .replace("#51a2da", Theme.primary.toString())
                                    .replace("#fafafa", Theme.primaryText.toString()))
                                sourceSize: Qt.size(176, 176)
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 88
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                                fillMode: Image.PreserveAspectFit
                                opacity: 0.92
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 7
                                Repeater {
                                    model: root.fetch.concat([["UP", DgopService.shortUptime.replace(/^up /, "") || "—"]])
                                    RowLayout {
                                        id: fetchRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Label {
                                            text: fetchRow.modelData[0]
                                            Layout.preferredWidth: 52
                                            font.letterSpacing: 1
                                        }
                                        Text {
                                            text: fetchRow.modelData[1]
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            font.family: root.mono
                                            font.pixelSize: 12
                                            color: root.mist
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            spacing: 8
                            Repeater {
                                model: root.swatches
                                Rectangle {
                                    required property color modelData
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: modelData
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.1)
                                }
                            }
                        }
                    }
                }

                Card {
                    id: mediaCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 172
                    readonly property var player: MprisController.activePlayer
                    readonly property string art: TrackArtService.resolvedArtUrl || player?.trackArtUrl || ""

                    Timer {
                        interval: 1000
                        repeat: true
                        running: mediaCard.player?.isPlaying ?? false
                        onTriggered: mediaCard.player.positionChanged()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            Rectangle {
                                Layout.preferredWidth: 72
                                Layout.preferredHeight: 72
                                radius: 16
                                color: Theme.withAlpha(root.tide, 0.6)
                                DankIcon {
                                    anchors.centerIn: parent
                                    name: "music_note"
                                    size: 28
                                    color: root.fog
                                    visible: artImage.status !== Image.Ready
                                }
                                Rounded {
                                    id: artImage
                                    anchors.fill: parent
                                    radius: 16
                                    source: mediaCard.art
                                    visible: mediaCard.art !== ""
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Label {
                                    text: mediaCard.player?.isPlaying ? "SONANDO" : mediaCard.player ? "EN PAUSA" : "MÚSICA"
                                }
                                Body {
                                    Layout.fillWidth: true
                                    text: mediaCard.player?.trackTitle || "Nada sonando"
                                    font.pixelSize: 16
                                    font.weight: Font.Medium
                                    color: mediaCard.player ? root.moon : root.fog
                                }
                                Body {
                                    Layout.fillWidth: true
                                    text: mediaCard.player?.trackArtist || "Pon algo de música"
                                    color: root.fog
                                    font.pixelSize: 13
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 3
                                radius: 2
                                color: Qt.rgba(1, 1, 1, 0.08)
                                Rectangle {
                                    height: parent.height
                                    radius: 2
                                    color: root.mist
                                    width: mediaCard.player && mediaCard.player.length > 0 ? parent.width * Math.min(1, mediaCard.player.position / mediaCard.player.length) : 0
                                }
                            }
                            Repeater {
                                model: ["skip_previous", mediaCard.player?.isPlaying ? "pause" : "play_arrow", "skip_next"]
                                Rectangle {
                                    id: mediaButton
                                    required property string modelData
                                    required property int index
                                    readonly property bool main: index === 1
                                    implicitWidth: main ? 38 : 30
                                    implicitHeight: implicitWidth
                                    radius: width / 2
                                    color: main ? root.moon : mediaHover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                                    opacity: mediaCard.player ? 1 : 0.4
                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: mediaButton.modelData
                                        size: mediaButton.main ? 20 : 18
                                        filled: true
                                        color: mediaButton.main ? root.ink : root.mist
                                    }
                                    MouseArea {
                                        id: mediaHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const p = mediaCard.player;
                                            if (mediaButton.index === 0)
                                                p?.previous();
                                            else if (mediaButton.index === 1)
                                                p?.togglePlaying();
                                            else
                                                p?.next();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Centro: hora, el wallpaper como planeta, contraseña ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Logo de niri pequeño arriba al centro (github.com/niri-wm/niri, docs/wiki/logo/niri-icon.svg)
                Image {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    source: "file://" + Quickshell.env("HOME") + "/.local/share/fedora-niri/niri-icon.svg"
                    sourceSize: Qt.size(88, 88)
                    fillMode: Image.PreserveAspectFit
                }

                Item {
                    Layout.fillHeight: true
                }

                // Hora: dígitos altos con degradado de luz de luna; minutos apilados a la derecha
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    Item {
                        width: hourText.implicitWidth
                        height: hourText.implicitHeight
                        Text {
                            id: hourText
                            text: SettingsData.use24HourClock ? Qt.formatTime(clock.date, "HH") : Qt.formatTime(clock.date, "hh AP").split(" ")[0]
                            font.family: root.display
                            font.pixelSize: 190
                            font.weight: Font.DemiBold
                            color: "white"
                            visible: false
                            layer.enabled: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop {
                                    position: 0.15
                                    color: root.moon
                                }
                                GradientStop {
                                    position: 0.9
                                    color: Theme.primary
                                }
                            }
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: hourText
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }
                        }
                    }
                    Column {
                        topPadding: 30
                        spacing: 2
                        Text {
                            text: Qt.formatTime(clock.date, "mm")
                            font.family: root.display
                            font.pixelSize: 84
                            font.weight: Font.Light
                            color: root.mist
                        }
                        Text {
                            text: SettingsData.use24HourClock ? "" : Qt.formatTime(clock.date, "hh AP").split(" ")[1]
                            font.family: root.display
                            font.pixelSize: 30
                            font.weight: Font.Normal
                            font.letterSpacing: 2
                            color: root.fog
                        }
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -6
                    text: clock.date.toLocaleDateString(Qt.locale(), "dddd · d MMMM").toUpperCase()
                    font.family: root.display
                    font.pixelSize: 22
                    font.weight: Font.Normal
                    font.letterSpacing: 5
                    color: root.mist
                }

                // El wallpaper como planeta con anillo: la mitad de atrás del anillo va detrás de
                // la foto y la de adelante encima, así el anillo "rodea" la foto
                Item {
                    id: planet
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 34
                    Layout.preferredWidth: 420
                    Layout.preferredHeight: 250
                    scale: Math.min(1, parent.width / 420)
                    readonly property real d: 230

                    Rectangle {
                        anchors.centerIn: parent
                        width: planet.d
                        height: planet.d
                        radius: width / 2
                        color: root.tide
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: Theme.primary
                            shadowBlur: 1.0
                            shadowOpacity: 0.45
                            shadowHorizontalOffset: 0
                            shadowVerticalOffset: 0
                        }
                    }
                    // Ondas con la música: el borde del planeta late con las 6 bandas de cava
                    // (cava escucha la salida, así que el volumen ya va incluido)
                    Shape {
                        id: waves
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        readonly property bool live: (MprisController.activePlayer?.isPlaying ?? false) && (Window.window?.visible ?? false)
                        property var levels: [0, 0, 0, 0, 0, 0]
                        property real phase: 0
                        opacity: live ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 500
                            }
                        }

                        function ring(amp, twist) {
                            const pts = [], n = 120, R = planet.d / 2 + 2, L = levels;
                            for (let i = 0; i <= n; i++) {
                                const t = i / n * 2 * Math.PI;
                                // bandas espejadas alrededor: graves arriba, agudos abajo, sin salto al cerrar
                                const p = i / n * 10, b = p <= 5 ? p : 10 - p, k = Math.floor(b), f = (1 - Math.cos((b - k) * Math.PI)) / 2;
                                const lvl = L[k] * (1 - f) + L[Math.min(5, k + 1)] * f;
                                const r = R + amp * lvl * (0.75 + 0.25 * Math.sin(5 * t + phase * twist));
                                pts.push(Qt.point(width / 2 + r * Math.sin(t), height / 2 - r * Math.cos(t)));
                            }
                            return pts;
                        }

                        Loader {
                            active: waves.live
                            sourceComponent: Component {
                                Ref {
                                    service: CavaService
                                }
                            }
                        }
                        Connections {
                            target: CavaService
                            enabled: waves.live
                            function onValuesChanged() {
                                waves.levels = CavaService.values.map(x => x > 0 ? Math.sqrt(Math.min(1, x / 25)) : 0);
                                waves.phase += 0.08;
                            }
                        }

                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: Theme.withAlpha(Theme.primary, 0.16)
                            PathPolyline {
                                path: waves.ring(30, 1)
                            }
                        }
                        ShapePath {
                            strokeColor: Theme.withAlpha(root.moon, 0.45)
                            strokeWidth: 1.5
                            fillColor: "transparent"
                            PathPolyline {
                                path: waves.ring(18, -1.6)
                            }
                        }
                    }
                    Orbit {
                        from: 180
                    }
                    Rounded {
                        anchors.centerIn: parent
                        width: planet.d
                        height: planet.d
                        radius: planet.d / 2
                        source: root.wallpaper
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: planet.d
                        height: planet.d
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.18)
                    }
                    Orbit {
                        from: 0
                    }
                    Rectangle {
                        // una lunita sobre el anillo: mismo punto de la elipse (198×42) y la misma rotación (-14°)
                        readonly property real t: -25 * Math.PI / 180
                        readonly property real r: -14 * Math.PI / 180
                        readonly property real ex: 198 * Math.cos(t)
                        readonly property real ey: 42 * Math.sin(t)
                        x: planet.width / 2 + ex * Math.cos(r) - ey * Math.sin(r) - width / 2
                        y: planet.height / 2 + ex * Math.sin(r) + ey * Math.cos(r) - height / 2
                        width: 10
                        height: 10
                        radius: 5
                        color: root.moon
                    }
                    // rueda sobre el planeta = volumen
                    MouseArea {
                        anchors.centerIn: parent
                        width: planet.d
                        height: planet.d
                        acceptedButtons: Qt.NoButton
                        onWheel: wheel => volumeBar.wheel(wheel.angleDelta.y)
                    }
                }

                // Volumen sin OSD: cápsula de vidrio con icono (silencio), −, barrita (clic, arrastre o rueda), + y %
                Rectangle {
                    id: volumeBar
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 16
                    implicitWidth: volRow.implicitWidth + 28
                    implicitHeight: 40
                    radius: 20
                    color: Theme.withAlpha(root.ink, 0.45)
                    border.width: 1
                    border.color: volHover.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.1)
                    opacity: AudioService.sink?.audio ? 1 : 0.4
                    Behavior on border.color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    readonly property bool muted: AudioService.sink?.audio?.muted ?? false
                    readonly property int pct: Math.round((AudioService.sink?.audio?.volume ?? 0) * 100)
                    readonly property real ratio: AudioService.sinkMaxVolume > 0 ? Math.min(1, pct / AudioService.sinkMaxVolume) : 0
                    property real acc: 0

                    function set(v) {
                        if (!AudioService.sink?.audio)
                            return;
                        SessionData.suppressOSDTemporarily();
                        AudioService.setVolume(Math.round(v));
                    }
                    function nudge(step) {
                        set(pct + step);
                    }
                    // el touchpad manda deltas chiquitos: se acumulan hasta un "clic" de rueda (5%)
                    function wheel(dy) {
                        acc += dy;
                        const n = Math.trunc(acc / 120);
                        if (n !== 0) {
                            acc -= n * 120;
                            nudge(n * 5);
                        }
                    }

                    HoverHandler {
                        id: volHover
                    }
                    WheelHandler {
                        onWheel: ev => volumeBar.wheel(ev.angleDelta.y)
                    }

                    Row {
                        id: volRow
                        anchors.centerIn: parent
                        spacing: 6

                        VolButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: volumeBar.muted || volumeBar.pct === 0 ? "volume_off" : volumeBar.pct < 40 ? "volume_down" : "volume_up"
                            iconSize: 18
                            accent: !volumeBar.muted
                            onClicked: {
                                SessionData.suppressOSDTemporarily();
                                AudioService.toggleMute();
                            }
                        }
                        VolButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "remove"
                            onClicked: volumeBar.nudge(-5)
                        }
                        Item {
                            id: track
                            anchors.verticalCenter: parent.verticalCenter
                            width: 140
                            height: 28
                            readonly property real fill: width * volumeBar.ratio
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Qt.rgba(1, 1, 1, 0.1)
                            }
                            // mismo degradado que la hora: luna → color del fondo
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(4, track.fill)
                                height: 4
                                radius: 2
                                opacity: volumeBar.muted ? 0.35 : 1
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop {
                                        position: 0
                                        color: root.moon
                                    }
                                    GradientStop {
                                        position: 1
                                        color: Theme.primary
                                    }
                                }
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 120
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                            // perilla: aparece al pasar el mouse
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(track.width - width, track.fill - width / 2))
                                width: trackMouse.pressed ? 14 : 12
                                height: width
                                radius: width / 2
                                color: root.moon
                                opacity: volHover.hovered ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 180
                                    }
                                }
                                Behavior on x {
                                    NumberAnimation {
                                        duration: 120
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                            MouseArea {
                                id: trackMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: mouse => volumeBar.set(Math.max(0, Math.min(1, mouse.x / width)) * AudioService.sinkMaxVolume)
                                onPositionChanged: mouse => volumeBar.set(Math.max(0, Math.min(1, mouse.x / width)) * AudioService.sinkMaxVolume)
                            }
                        }
                        VolButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "add"
                            onClicked: volumeBar.nudge(5)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            horizontalAlignment: Text.AlignRight
                            text: volumeBar.muted ? "—" : volumeBar.pct + "%"
                            font.family: root.sans
                            font.pixelSize: 13
                            font.features: {
                                "tnum": 1
                            }
                            color: root.mist
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 18
                    readonly property int h: clock.date.getHours()
                    readonly property string first: (UserInfoService.fullName || UserInfoService.username || Quickshell.env("USER")).split(" ")[0]
                    text: (h >= 5 && h < 12 ? "Buenos días, " : h >= 12 && h < 19 ? "Buenas tardes, " : "Buenas noches, ") + first
                    font.family: root.sans
                    font.pixelSize: 17
                    color: root.mist
                }

                // Contraseña (solo bloqueado)
                Rectangle {
                    id: passwordBox
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 16
                    implicitWidth: 330
                    implicitHeight: 50
                    radius: 25
                    visible: root.locked
                    color: Theme.withAlpha(root.ink, 0.5)
                    border.width: 1
                    border.color: root.pamState !== "" ? root.ember : passwordField.text !== "" ? Theme.primary : passwordField.activeFocus ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(1, 1, 1, 0.15)

                    // Efecto al escribir: cada tecla lanza un anillo del color del fondo que se expande y se desvanece
                    Rectangle {
                        id: typePulse
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.primary
                        opacity: 0
                        ParallelAnimation {
                            id: typePulseAnim
                            NumberAnimation {
                                target: typePulse
                                property: "opacity"
                                from: 0.8
                                to: 0
                                duration: 420
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: typePulse
                                property: "scale"
                                from: 1
                                to: 1.08
                                duration: 420
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    DankIcon {
                        id: lockGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.unlocking ? "lock_open" : "lock"
                        size: 18
                        color: passwordField.text !== "" ? Theme.primary : root.fog
                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                    }
                    TextInput {
                        id: passwordField
                        anchors.left: lockGlyph.right
                        anchors.right: submitButton.left
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        focus: root.locked
                        enabled: root.locked
                        readOnly: root.unlocking || (root.pam?.passwd.active ?? false)
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        font.family: root.sans
                        font.pixelSize: 16
                        font.letterSpacing: 2
                        color: "transparent" // los caracteres se dibujan como cuadrados en passwordSquares
                        selectionColor: root.tide
                        clip: true

                        // Cuadrados con esquinas redondeadas en vez de puntos; si no caben, se ven los últimos
                        Item {
                            anchors.fill: parent
                            clip: true
                            Row {
                                id: passwordSquares
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.min(0, parent.width - width)
                                spacing: 6
                                Repeater {
                                    model: passwordField.text.length
                                    Rectangle {
                                        width: 10
                                        height: 10
                                        radius: 3
                                        color: root.moon
                                    }
                                }
                            }
                        }
                        onTextChanged: {
                            root.passwordEdited(text);
                            if (text !== "")
                                typePulseAnim.restart();
                        }
                        onAccepted: root.submit()
                        Keys.onEscapePressed: text = ""

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Contraseña"
                            visible: parent.text === ""
                            font.family: root.sans
                            font.pixelSize: 15
                            color: root.fog
                        }
                    }
                    Rectangle {
                        id: submitButton
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: 18
                        color: passwordField.text !== "" ? root.moon : Qt.rgba(1, 1, 1, 0.06)
                        DankIcon {
                            anchors.centerIn: parent
                            name: "arrow_forward"
                            size: 18
                            color: passwordField.text !== "" ? root.ink : root.fog
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submit()
                        }
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: root.locked ? 10 : 18
                    Layout.preferredHeight: 18
                    text: root.locked ? root.feedback() : "ESC PARA CERRAR"
                    font.family: root.locked ? root.sans : root.mono
                    font.pixelSize: root.locked ? 13 : 10
                    font.letterSpacing: root.locked ? 0 : 2
                    color: root.pamState !== "" ? root.ember : root.fog
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            // ── Derecha: sistema y notificaciones ────────────────────
            ColumnLayout {
                Layout.preferredWidth: 380
                Layout.minimumWidth: 330
                Layout.fillHeight: true
                spacing: 16

                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 310

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 12

                        CardTitle {
                            Layout.fillWidth: true
                            icon: "memory"
                            title: "Sistema"
                            aside: (DgopService.cpuFrequency > 0 ? (DgopService.cpuFrequency / 1000).toFixed(1) + " GHz" : "") + (DgopService.cpuTemperature > 0 ? "  ·  " + Math.round(DgopService.cpuTemperature) + "°C" : "")
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 104
                            Layout.maximumHeight: 104
                            spacing: 10
                            Gauge {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.maximumWidth: 104
                                Layout.alignment: Qt.AlignHCenter
                                value: DgopService.cpuUsage
                                text: Math.round(DgopService.cpuUsage) + "%"
                                label: "CPU"
                            }
                            Gauge {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.maximumWidth: 104
                                Layout.alignment: Qt.AlignHCenter
                                value: DgopService.memoryUsage
                                text: Math.round(DgopService.memoryUsage) + "%"
                                label: "RAM"
                            }
                            Gauge {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.maximumWidth: 104
                                Layout.alignment: Qt.AlignHCenter
                                readonly property bool bat: BatteryService.batteryAvailable
                                value: bat ? BatteryService.batteryLevel : DgopService.cpuTemperature
                                tint: bat && BatteryService.batteryLevel <= 15 ? root.ember : root.mist
                                text: bat ? Math.round(BatteryService.batteryLevel) + "%" : Math.round(DgopService.cpuTemperature) + "°"
                                label: bat ? "BAT" : "TEMP"
                                icon: bat && BatteryService.isCharging ? "bolt" : ""
                            }
                            Gauge {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.maximumWidth: 104
                                Layout.alignment: Qt.AlignHCenter
                                value: root.disk ? 100 * root.disk.used / root.disk.total : 0
                                text: Math.round(value) + "%"
                                label: "DISCO"
                            }
                        }
                        Body {
                            Layout.fillWidth: true
                            visible: root.disk !== null
                            font.pixelSize: 12
                            text: root.disk ? "Disco de " + root.gb(root.disk.total) + " GB  ·  " + root.gb(root.disk.used) + " GB usados  ·  " + root.gb(root.disk.available) + " GB libres" : ""
                        }
                        Body {
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            text: "Carpeta personal  " + (root.home < 0 ? "calculando…" : root.gb(root.home) + " GB")
                        }

                        // Carga de CPU del último minuto
                        Canvas {
                            id: spark
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Connections {
                                target: DgopService
                                function onCpuUsageChanged() {
                                    spark.requestPaint();
                                }
                            }
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.08);
                                ctx.fillRect(0, height - 1, width, 1);
                                const h = DgopService.cpuHistory || [];
                                if (h.length < 2)
                                    return;
                                const n = DgopService.historySize;
                                const step = width / (n - 1);
                                const x0 = width - (h.length - 1) * step;
                                const yOf = v => height - 2 - (height - 4) * Math.min(100, v) / 100;
                                ctx.beginPath();
                                ctx.moveTo(x0, height);
                                for (let i = 0; i < h.length; i++)
                                    ctx.lineTo(x0 + i * step, yOf(h[i]));
                                ctx.lineTo(width, height);
                                ctx.closePath();
                                const g = ctx.createLinearGradient(0, 0, 0, height);
                                g.addColorStop(0, Theme.withAlpha(root.mist, 0.28));
                                g.addColorStop(1, Theme.withAlpha(root.mist, 0));
                                ctx.fillStyle = g;
                                ctx.fill();
                                ctx.beginPath();
                                for (let i = 0; i < h.length; i++)
                                    i === 0 ? ctx.moveTo(x0, yOf(h[0])) : ctx.lineTo(x0 + i * step, yOf(h[i]));
                                ctx.strokeStyle = root.mist;
                                ctx.lineWidth = 1.5;
                                ctx.lineJoin = "round";
                                ctx.stroke();
                            }
                            Label {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                text: "CARGA DE CPU"
                                font.pixelSize: 9
                            }
                        }
                    }
                }

                Card {
                    id: notifs
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Privacidad: bloqueado respeta el ajuste de DMS (0 nada, 1 solo cantidad,
                    // 2 solo apps, 3 todo); desbloqueado muestra todo
                    readonly property int mode: root.locked ? SettingsData.lockScreenNotificationMode : 3
                    readonly property var all: Array.from(NotificationService.notifications).reverse()
                    readonly property var rows: {
                        if (mode === 3)
                            return all.slice(0, 7).map(n => ({
                                        "app": n.appName,
                                        "time": n.timeStr,
                                        "text": n.summary,
                                        "image": n.displayImage,
                                        "icon": n.fallbackIconName
                                    }));
                        const apps = {};
                        for (const n of all) {
                            if (!apps[n.appName])
                                apps[n.appName] = {
                                    "app": n.appName,
                                    "time": "",
                                    "count": 0,
                                    "image": n.displayImage,
                                    "icon": n.fallbackIconName
                                };
                            apps[n.appName].count++;
                        }
                        return Object.values(apps).slice(0, 7).map(a => Object.assign(a, {
                                    "text": a.count === 1 ? "1 notificación" : a.count + " notificaciones"
                                }));
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16

                        CardTitle {
                            Layout.fillWidth: true
                            icon: "notifications"
                            title: "Notificaciones"
                            aside: notifs.all.length > 0 ? String(notifs.all.length) : ""
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            visible: notifs.mode >= 2 && notifs.all.length > 0
                            Repeater {
                                model: notifs.mode >= 2 ? notifs.rows : []
                                RowLayout {
                                    id: notifRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 12
                                    DankCircularImage {
                                        Layout.preferredWidth: 34
                                        Layout.preferredHeight: 34
                                        Layout.alignment: Qt.AlignTop
                                        imageSource: notifRow.modelData.image || ""
                                        fallbackIcon: notifRow.modelData.icon || ""
                                        fallbackText: (notifRow.modelData.app || "?").charAt(0).toUpperCase()
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Body {
                                                Layout.fillWidth: true
                                                text: notifRow.modelData.app
                                                font.pixelSize: 13
                                                font.weight: Font.Medium
                                                color: root.moon
                                            }
                                            Label {
                                                text: notifRow.modelData.time
                                                font.letterSpacing: 0
                                            }
                                        }
                                        Body {
                                            Layout.fillWidth: true
                                            text: notifRow.modelData.text
                                            visible: text !== ""
                                            font.pixelSize: 13
                                            color: root.fog
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                visible: notifs.all.length === 0 || notifs.mode < 2
                                DankIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: notifs.all.length === 0 ? "notifications_off" : "lock"
                                    size: 32
                                    color: root.fog
                                }
                                Body {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: notifs.all.length === 0 ? "Todo al día" : notifs.mode === 1 ? (notifs.all.length === 1 ? "1 notificación" : notifs.all.length + " notificaciones") : "Ocultas mientras está bloqueado"
                                    color: root.fog
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
