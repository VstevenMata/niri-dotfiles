import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// ~/.local/bin/theme escribe la hora de entrada a zen en ~/.local/state/theme-zen-since.
// Modo foco (pomodoro) opcional dentro de zen: ~/.local/state/zen-focus-since guarda cuándo empezó,
// o 0 si está apagado. Ciclos de foco + pausa, 25/5 o 50/20 (~/.local/state/zen-pomodoro).
// Cambiar de ciclo o reiniciar vuelve a empezar el pomodoro; el tiempo en zen sigue corriendo.
PluginComponent {
    id: root

    property real since: 0
    property real now: Date.now() / 1000
    readonly property int elapsed: since > 0 ? Math.max(0, now - since) : 0
    property real focusSince: 0
    readonly property bool focusOn: focusSince > 0
    readonly property int fElapsed: focusOn ? Math.max(0, now - focusSince) : 0
    property int focusMin: 25
    readonly property int breakMin: focusMin === 50 ? 20 : 5
    readonly property int focusSec: focusMin * 60
    readonly property int cycleSec: (focusMin + breakMin) * 60
    readonly property int inCycle: fElapsed % cycleSec
    readonly property bool working: inCycle < focusSec
    readonly property int remaining: working ? focusSec - inCycle : cycleSec - inCycle
    readonly property real progress: !focusOn ? 0 : working ? inCycle / focusSec : (inCycle - focusSec) / (cycleSec - focusSec)
    readonly property int done: Math.floor(fElapsed / cycleSec)

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/zen-pomodoro"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.focusMin = parseInt(text()) === 50 ? 50 : 25
    }
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/zen-focus-since"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.focusSince = parseFloat(text()) || 0
    }
    // Al empezar el foco (activarlo o entrar en zen con él puesto) se abre el popout del reloj, en la
    // pantalla enfocada. No al reiniciar ni al recargar DMS (solo si el inicio es de hace segundos).
    onFocusSinceChanged: {
        const fresh = prevFS <= 0 && focusSince > 0 && Date.now() / 1000 - focusSince < 15 && !fromPopout;
        prevFS = focusSince;
        fromPopout = false;
        if (fresh && (!parentScreen || parentScreen.name === NiriService.currentOutput))
            Qt.callLater(triggerPopout);
    }
    property real prevFS: 0
    property bool fromPopout: false   // activado desde el popout: ya está abierto (toggle lo cerraría)
    function restartFocus(extra) {
        Quickshell.execDetached(["sh", "-c", (extra || "") + "date +%s > ~/.local/state/zen-focus-since"]);
    }
    function setPreset(m) {
        if (m !== focusMin) restartFocus("echo " + m + " > ~/.local/state/zen-pomodoro; ");
    }
    function toggleFocus() {
        if (focusOn) Quickshell.execDetached(["sh", "-c", "echo 0 > ~/.local/state/zen-focus-since"]);
        else { fromPopout = true; restartFocus(); }
    }
    readonly property color accent: working ? Theme.surfaceText : "#E3DAC9"   // pausa en color hueso

    // Al cambiar de foco a pausa y viceversa: suena un cuenco (~/.config/dms-sounds) y la propia
    // pastilla del reloj muestra el mensaje 9 s. Solo cuando lo produce el paso del tiempo,
    // no al cargar ni al reiniciar el contador.
    property bool msgShown: false
    property string msgTitle: ""
    property string msgText: ""
    Timer { id: msgTimer; interval: 9000; onTriggered: root.msgShown = false }
    // Fase = (ciclo, foco/pausa). Se compara en cada segundo; si cambió el inicio del foco
    // (reinicio, cambio de ciclo, archivo reescrito) no avisa.
    property real lastFS: -1
    property int lastPhase: -1
    function checkPhase() {
        const phase = done * 2 + (working ? 0 : 1);
        if (focusOn && focusSince === lastFS && lastPhase >= 0 && phase !== lastPhase) announce();
        lastFS = focusSince;
        lastPhase = phase;
    }
    function announce() {
        Quickshell.execDetached(["pw-play", "--volume", "0.6", Quickshell.env("HOME") + "/.config/dms-sounds/" + (working ? "zen-foco.wav" : "zen-pausa.wav")]);
        msgTitle = working ? "De vuelta al foco" : "Pausa de " + breakMin + " min";
        msgText = working ? "Pomodoro " + (done + 1) + " · " + focusMin + " min" : "Estírate y mira lejos";
        msgShown = true;
        msgTimer.restart();
    }

    function pad(n) { return n < 10 ? "0" + n : "" + n }
    function hm(s) { return Math.floor(s / 3600) + ":" + pad(Math.floor(s / 60) % 60) }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/theme-zen-since"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.since = parseFloat(text()) || 0
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: { root.now = Date.now() / 1000; root.checkPhase() } }

    // Anillo de progreso del pomodoro
    component Ring: Canvas {
        property real stroke: 2
        property real value: root.progress
        onValueChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"), r = width / 2 - stroke;
            c.reset();
            c.lineWidth = stroke; c.lineCap = "round";
            c.strokeStyle = Theme.withAlpha(Theme.surfaceText, 0.12);
            c.beginPath(); c.arc(width / 2, height / 2, r, 0, 2 * Math.PI); c.stroke();
            c.strokeStyle = root.accent;
            c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * value); c.stroke();
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: 7
            Ring { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; visible: root.focusOn }
            DankIcon { name: "spa"; size: 15; anchors.verticalCenter: parent.verticalCenter; visible: !root.focusOn; color: Theme.surfaceText; opacity: 0.7 }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.msgShown
                text: root.hm(root.elapsed) + ":" + root.pad(root.elapsed % 60)
                font.pixelSize: Theme.fontSizeSmall
                font.features: { "tnum": 1 }
                color: Theme.surfaceText
                opacity: 0.85
            }
            // En qué estamos: Foco / Pausa con lo que falta
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.focusOn && !root.msgShown
                text: (root.working ? "Foco " : "Pausa ") + Math.floor(root.remaining / 60) + "′"
                font.pixelSize: Theme.fontSizeSmall
                color: root.working ? Theme.surfaceText : root.accent
                opacity: 0.5
            }
            // Mensaje al cambiar de fase, como una burbuja dentro de la barra
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.msgShown
                width: msgRow.implicitWidth + 22; height: 24; radius: 12
                color: root.working ? Theme.withAlpha(Theme.surfaceText, 0.1) : Qt.rgba(0.89, 0.855, 0.79, 0.14)
                border.width: 1
                border.color: root.working ? Theme.withAlpha(Theme.surfaceText, 0.12) : Qt.rgba(0.89, 0.855, 0.79, 0.32)
                Row {
                    id: msgRow
                    anchors.centerIn: parent
                    spacing: 7
                    DankIcon { anchors.verticalCenter: parent.verticalCenter; name: root.working ? "self_improvement" : "local_cafe"; size: 15; color: root.accent }
                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: root.msgTitle; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.DemiBold; color: Theme.surfaceText }
                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: root.msgText; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText; opacity: 0.6 }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.msgShown = false }
            }
        }
    }

    // Reloj con sus controles: lo usan el popout y la ventana grande
    component Panel:Column {
        property real k: 1   // tamaño de la esfera (1 en el popout, más en la ventana)
        width: Math.max(260, 210 * k)
        spacing: 18

        // Esfera: disco con luz suave, 60 marcas, arco con degradado y punto luminoso en la punta
        Item {
            id: dial
            width: 210 * parent.k; height: width
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real r: 88 * parent.k

            Canvas {
                id: face
                anchors.fill: parent
                property real p: root.progress
                property bool w: root.working
                property bool on: root.focusOn
                onPChanged: requestPaint()
                onWChanged: requestPaint()
                onOnChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d"), cx = width / 2, cy = height / 2, R = dial.r;
                    const a = root.accent;
                    c.reset();
                    // disco: luz tenue en el centro
                    const bg = c.createRadialGradient(cx, cy - 20, 10, cx, cy, R + 14);
                    bg.addColorStop(0, Theme.withAlpha(Theme.surfaceText, 0.06));
                    bg.addColorStop(1, Theme.withAlpha(Theme.surfaceText, 0.012));
                    c.fillStyle = bg;
                    c.beginPath(); c.arc(cx, cy, R + 14, 0, 2 * Math.PI); c.fill();
                    c.strokeStyle = Theme.withAlpha(Theme.surfaceText, 0.06); c.lineWidth = 1;
                    c.beginPath(); c.arc(cx, cy, R + 14, 0, 2 * Math.PI); c.stroke();
                    // marcas: 60, cada 5 más largas; las ya recorridas se encienden
                    for (let i = 0; i < 60; i++) {
                        const ang = -Math.PI / 2 + i * Math.PI / 30, major = i % 5 === 0;
                        const lit = on && i / 60 <= p;
                        const r1 = R - 12, r2 = R - (major ? 20 : 15);
                        c.strokeStyle = lit ? Qt.rgba(a.r, a.g, a.b, major ? 0.8 : 0.45) : Theme.withAlpha(Theme.surfaceText, major ? 0.22 : 0.08);
                        c.lineWidth = major ? 2 : 1;
                        c.lineCap = "round";
                        c.beginPath();
                        c.moveTo(cx + r1 * Math.cos(ang), cy + r1 * Math.sin(ang));
                        c.lineTo(cx + r2 * Math.cos(ang), cy + r2 * Math.sin(ang));
                        c.stroke();
                    }
                    // pista del arco
                    c.strokeStyle = Theme.withAlpha(Theme.surfaceText, 0.07); c.lineWidth = 5;
                    c.beginPath(); c.arc(cx, cy, R, 0, 2 * Math.PI); c.stroke();
                    if (!on || p <= 0) return;
                    // arco con degradado: tenue al inicio, pleno en la punta
                    const start = -Math.PI / 2, endA = start + 2 * Math.PI * p, steps = Math.max(2, Math.ceil(p * 90));
                    c.lineCap = "round"; c.lineWidth = 5;
                    for (let i = 0; i < steps; i++) {
                        const t0 = i / steps, t1 = (i + 1) / steps;
                        c.strokeStyle = Qt.rgba(a.r, a.g, a.b, 0.18 + 0.8 * t1);
                        c.beginPath(); c.arc(cx, cy, R, start + (endA - start) * t0, start + (endA - start) * t1 + 0.004); c.stroke();
                    }
                    // punto luminoso en la punta
                    const kx = cx + R * Math.cos(endA), ky = cy + R * Math.sin(endA);
                    const glow = c.createRadialGradient(kx, ky, 0, kx, ky, 14);
                    glow.addColorStop(0, Qt.rgba(a.r, a.g, a.b, 0.45));
                    glow.addColorStop(1, Qt.rgba(a.r, a.g, a.b, 0));
                    c.fillStyle = glow;
                    c.beginPath(); c.arc(kx, ky, 14, 0, 2 * Math.PI); c.fill();
                    c.fillStyle = Theme.withAlpha(Theme.surfaceText, 1);
                    c.beginPath(); c.arc(kx, ky, 4.5, 0, 2 * Math.PI); c.fill();
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 4
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.focusOn ? (root.working ? "FOCO" : "PAUSA") : "EN ZEN"
                    font.pixelSize: 10 * Math.sqrt(dial.parent.k); font.letterSpacing: 3.5; font.weight: Font.Medium
                    color: root.accent; opacity: 0.7
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.focusOn ? Math.floor(root.remaining / 60) + ":" + root.pad(root.remaining % 60) : root.hm(root.elapsed)
                    font.pixelSize: 42 * dial.parent.k; font.weight: Font.ExtraLight
                    font.features: { "tnum": 1 }
                    color: Theme.surfaceText
                }
                // un punto por pomodoro: llenos los hechos, contorno el actual
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.focusOn
                    spacing: 6
                    height: 8
                    Repeater {
                        model: Math.min(6, root.done + 1)
                        Rectangle {
                            required property int index
                            readonly property bool current: index === Math.min(5, root.done)
                            width: 6; height: 6; radius: 3
                            color: current ? "transparent" : Theme.surfaceText
                            border.width: current ? 1 : 0
                            border.color: Theme.surfaceText
                            opacity: current ? 0.7 : 0.55
                        }
                    }
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 36
            Column {
                StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: root.hm(root.elapsed) + ":" + root.pad(root.elapsed % 60); font.pixelSize: 18; font.features: { "tnum": 1 }; color: Theme.surfaceText }
                StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: "en zen"; font.pixelSize: 11; color: Theme.surfaceText; opacity: 0.5 }
            }
            Column {
                visible: root.focusOn
                StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: root.done; font.pixelSize: 18; color: Theme.surfaceText }
                StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: root.done === 1 ? "pomodoro" : "pomodoros"; font.pixelSize: 11; color: Theme.surfaceText; opacity: 0.5 }
            }
        }

        // Interruptor del modo foco
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220; height: 40; radius: 20
            color: root.focusOn ? Theme.withAlpha(Theme.surfaceText, fma.containsMouse ? 0.2 : 0.14) : Theme.withAlpha(Theme.surfaceText, fma.containsMouse ? 0.1 : 0.05)
            border.width: 1; border.color: Theme.withAlpha(Theme.surfaceText, root.focusOn ? 0.18 : 0.06)
            Row {
                anchors.centerIn: parent
                spacing: 8
                DankIcon { anchors.verticalCenter: parent.verticalCenter; name: root.focusOn ? "timer_off" : "timer"; size: 18; color: Theme.surfaceText }
                StyledText { anchors.verticalCenter: parent.verticalCenter; text: root.focusOn ? "Desactivar foco" : "Activar foco"; font.pixelSize: 13; font.weight: Font.Medium; color: Theme.surfaceText }
            }
            MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleFocus() }
        }

        // Elegir ciclo: 25/5 o 50/20
        Rectangle {
            visible: root.focusOn
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220; height: 34; radius: 17
            color: Theme.withAlpha(Theme.surfaceText, 0.05)
            border.width: 1; border.color: Theme.withAlpha(Theme.surfaceText, 0.06)
            Row {
                anchors.fill: parent; anchors.margins: 3
                Repeater {
                    model: [{ m: 25, t: "25 · 5" }, { m: 50, t: "50 · 20" }]
                    Rectangle {
                        required property var modelData
                        width: parent.width / 2; height: parent.height; radius: height / 2
                        color: root.focusMin === modelData.m ? Theme.withAlpha(Theme.surfaceText, 0.14) : "transparent"
                        StyledText { anchors.centerIn: parent; text: modelData.t + " min"; font.pixelSize: 12; color: Theme.surfaceText; opacity: root.focusMin === modelData.m ? 1 : 0.55 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setPreset(parent.modelData.m) }
                    }
                }
            }
        }

        // Reiniciar el pomodoro (por si te levantas y vuelves)
        Rectangle {
            visible: root.focusOn
            anchors.horizontalCenter: parent.horizontalCenter
            width: 120; height: 32; radius: 16
            color: rma.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.1) : Theme.withAlpha(Theme.surfaceText, 0.05)
            StyledText { anchors.centerIn: parent; text: "Reiniciar"; font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.8 }
            MouseArea {
                id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.restartFocus()
            }
        }
    }

    popoutWidth: 300
    popoutHeight: 460
    popoutContent: Component {
        PopoutComponent {
            Item {
                width: parent.width
                height: panel.height
                Panel { id: panel; width: parent.width }
                // Abrir el reloj en una ventana grande (como la de `musica`)
                DankIcon {
                    anchors { right: parent.right; top: parent.top }
                    name: "open_in_new"; size: 18; color: Theme.surfaceText
                    opacity: oma.containsMouse ? 1 : 0.6
                    MouseArea { id: oma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.closePopout(); bigWin.visible = !bigWin.visible } }
                }
            }
        }
    }

    // Ventana normal de niri, estilo terminal: solo lo que falta en dígitos ASCII y los pomodoros hechos.
    // Activar y elegir ciclo se hace en el popout. Se cierra con su atajo de cerrar ventana.
    readonly property var glyphs: ({
        "0": ["###", "# #", "# #", "# #", "###"], "1": ["  #", "  #", "  #", "  #", "  #"],
        "2": ["###", "  #", "###", "#  ", "###"], "3": ["###", "  #", "###", "  #", "###"],
        "4": ["# #", "# #", "###", "  #", "  #"], "5": ["###", "#  ", "###", "  #", "###"],
        "6": ["###", "#  ", "###", "# #", "###"], "7": ["###", "  #", "  #", "  #", "  #"],
        "8": ["###", "# #", "###", "# #", "###"], "9": ["###", "# #", "###", "  #", "###"],
        ":": [" ", "#", " ", "#", " "]
    })
    // Cada píxel son dos caracteres (█ es el doble de alto que de ancho): sale cuadrado
    function ascii(str) {
        const rows = [];
        for (let y = 0; y < 5; y++)
            rows.push(str.split("").map(ch => glyphs[ch][y].replace(/#/g, "██").replace(/ /g, "  ")).join("  "));
        return rows.join("\n");
    }
    FloatingWindow {
        id: bigWin
        visible: false
        title: "Pomodoro zen"
        implicitWidth: 640; implicitHeight: 340
        color: Theme.surface
        // Arrastrar desde cualquier punto de la ventana
        MouseArea { anchors.fill: parent; onPressed: bigWin.startSystemMove() }
        // Pantalla completa (Super+Enter): barras tipo cava arriba y el reloj abajo
        readonly property bool full: screen && width >= screen.width && height >= screen.height
        readonly property int nBars: 64
        property var bars: []
        Process {
            running: bigWin.visible && bigWin.full
            command: ["sh", "-c", "c=$XDG_RUNTIME_DIR/zen-cava.conf; printf '[general]\\nframerate=30\\nbars=" + bigWin.nBars + "\\n[output]\\nmethod=raw\\nraw_target=/dev/stdout\\ndata_format=ascii\\nascii_max_range=1000\\nchannels=mono\\n' > $c; exec cava -p $c < /dev/null"]
            stdout: SplitParser { onRead: data => bigWin.bars = data.split(";").slice(0, bigWin.nBars).map(Number) }
            onRunningChanged: if (!running) bigWin.bars = []
        }
        Row {
            visible: bigWin.full
            anchors { top: parent.top; left: parent.left; right: parent.right; bottom: clockCol.top; margins: 48 }
            spacing: 6
            Repeater {
                model: bigWin.nBars
                Rectangle {
                    required property int index
                    width: (parent.width - parent.spacing * (bigWin.nBars - 1)) / bigWin.nBars
                    height: Math.max(2, parent.height * (bigWin.bars[index] || 0) / 1000)
                    anchors.top: parent.top
                    radius: 2
                    color: root.accent; opacity: 0.45
                }
            }
        }
        Column {
            id: clockCol
            anchors.centerIn: bigWin.full ? undefined : parent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: bigWin.full ? parent.bottom : undefined
            anchors.bottomMargin: 64
            spacing: 24
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // 34 columnas x 5 filas para MM:SS
                font.pixelSize: Math.max(6, Math.min((bigWin.width - 60) / (34 * 0.6), (bigWin.full ? bigWin.height * 0.3 : bigWin.height - 120) / 5.3))
                font.family: "monospace"
                lineHeightMode: Text.FixedHeight; lineHeight: font.pixelSize * 1.05
                color: root.focusOn ? root.accent : Theme.withAlpha(Theme.surfaceText, 0.25)
                text: { const s = root.focusOn ? root.remaining : root.focusSec; return root.ascii(root.pad(Math.floor(s / 60)) + ":" + root.pad(s % 60)) }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: "monospace"; font.pixelSize: 14
                color: Theme.surfaceText; opacity: 0.6
                text: root.focusOn ? (root.working ? "foco" : "pausa") + "  ·  pomodoros: " + root.done : "foco apagado"
            }
        }
    }

    // En los bordes laterales: anillo (o hoja), horas:minutos y segundos tenues
    verticalBarPill: Component {
        Column {
            spacing: 3
            Ring { width: 14; height: 14; anchors.horizontalCenter: parent.horizontalCenter; visible: root.focusOn }
            DankIcon { name: "spa"; size: 15; anchors.horizontalCenter: parent.horizontalCenter; visible: !root.focusOn; color: Theme.surfaceText; opacity: 0.7 }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hm(root.elapsed)
                font.pixelSize: Theme.fontSizeSmall
                font.features: { "tnum": 1 }
                color: Theme.surfaceText
                opacity: 0.85
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.focusOn ? Math.floor(root.remaining / 60) + "′" : root.pad(root.elapsed % 60)
                font.pixelSize: 10
                font.features: { "tnum": 1 }
                color: root.focusOn && !root.working ? root.accent : Theme.surfaceText
                opacity: 0.5
            }
        }
    }
}
