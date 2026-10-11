import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Música en la barra: ⏮ ondas ⏭. Clic (o hover) abre el popout con carátula y controles.
// Las ondas salen de un cava propio con 24 barras; en silencio queda una línea de puntos quieta.
PluginComponent {
    id: root
    readonly property int n: 12
    property var levels: Array(n).fill(0)
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool playing: player?.isPlaying ?? false

    function fmt(s) { s = Math.max(0, Math.floor(s || 0)); return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + s % 60 }

    // Letra de LRCLIB (lrclib.net) para cualquier reproductor: sincronizada si hay, si no texto plano
    property var lyrics: []          // [{ t: segundos, text }]
    property string plainLyrics: ""
    property bool lyricsLoading: false
    readonly property string lyricsKey: player ? (player.trackArtist || "") + "|" + (player.trackTitle || "") : ""
    readonly property int lyricIndex: {
        const p = (player?.position ?? 0) + 0.3;
        let i = -1;
        for (let k = 0; k < lyrics.length && lyrics[k].t <= p; k++) i = k;
        return i;
    }
    readonly property bool isMusica: (player?.identity ?? "").toLowerCase().includes("mpv")

    // Espera un poco: la duración y el artista llegan después del título
    onLyricsKeyChanged: { lyrics = []; plainLyrics = ""; lyricsTimer.restart() }
    Timer { id: lyricsTimer; interval: 800; onTriggered: root.fetchLyrics() }

    function fetchLyrics() {
        const t = player?.trackTitle ?? "";
        if (!t) return;
        const q = (t.includes(" - ") ? t : (player.trackArtist || "") + " " + t)
            .replace(/\([^)]*\)|\[[^\]]*\]/g, "").replace(/[|｜].*/, "")
            .replace(/official.*|lyrics?/ig, "").replace(/["“”]/g, "").trim();
        lyricsProc.running = false;
        lyricsProc.command = ["curl", "-sf", "--max-time", "10", "--get", "--data-urlencode", "q=" + q, "https://lrclib.net/api/search"];
        lyricsLoading = true;
        lyricsProc.running = true;
    }

    function parseLyrics(txt) {
        let arr = [];
        try { arr = JSON.parse(txt) } catch (e) {}
        // Varias versiones (video, álbum…): la de duración más parecida
        const len = player?.length ?? 0, dif = r => len > 0 ? Math.abs((r.duration || 0) - len) : 0;
        const synced = arr.filter(r => r.syncedLyrics).sort((a, b) => dif(a) - dif(b));
        if (synced.length)
            lyrics = synced[0].syncedLyrics.split("\n").map(l => {
                const m = l.match(/^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$/);
                return m ? { t: +m[1] * 60 + +m[2], text: m[3] || "♪" } : null;
            }).filter(x => x);
        else
            plainLyrics = (arr.find(r => r.plainLyrics) || {}).plainLyrics || "";
        lyricsLoading = false;
    }

    Process {
        id: lyricsProc
        stdout: StdioCollector { onStreamFinished: root.parseLyrics(text) }
    }

    // Ventana de letra de `musica` (mpv): se abre/oculta por su socket
    Process {
        id: ventanaProc
        command: ["sh", "-c", `echo '{"command":["cycle","force-window"]}' | socat - "$XDG_RUNTIME_DIR/musica.sock"`]
    }

    Process {
        running: root.playing
        command: ["sh", "-c", `c=$(mktemp); cat > "$c" <<'CONF'
[general]
framerate=30
bars=${root.n}
sleep_timer=2
[output]
method=raw
data_format=ascii
ascii_max_range=100
channels=mono
[smoothing]
noise_reduction=70
monstercat=1
CONF
exec cava -p "$c" < /dev/null`]
        stdout: SplitParser {
            onRead: data => {
                const v = data.split(";").slice(0, root.n).map(x => (parseInt(x, 10) || 0) / 100);
                if (v.length === root.n) root.levels = v;
            }
        }
    }

    // Ondas fluidas: tres curvas finas que se entrelazan. Cada curva sigue una zona del sonido
    // (graves, medios, agudos) y se desvanece en los extremos. Solo se dibuja mientras suena música.
    property real phase: 0
    onLevelsChanged: phase += 0.18
    component Waves: Canvas {
        id: cv
        property real amp: 1
        width: 150; height: 22
        Connections { target: root; function onPhaseChanged() { cv.requestPaint() } }
        onPaint: {
            const c = getContext("2d"), w = width, h = height, mid = h / 2, L = root.levels, n = L.length;
            c.reset();
            const zone = (a, b) => { let s = 0; for (let i = a; i < b; i++) s += L[i]; return s / (b - a) };
            const curves = [
                { lv: zone(0, 3),  k: 1.6, sp: 1.0, a: 0.95, lw: 1.8 },
                { lv: zone(3, 7),  k: 2.6, sp: -1.4, a: 0.55, lw: 1.3 },
                { lv: zone(7, n),  k: 3.8, sp: 1.9, a: 0.35, lw: 1.0 }
            ];
            for (const cu of curves) {
                const g = c.createLinearGradient(0, 0, w, 0);
                const col = Theme.surfaceText;
                g.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0));
                g.addColorStop(0.5, Qt.rgba(col.r, col.g, col.b, cu.a));
                g.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0));
                c.strokeStyle = g; c.lineWidth = cu.lw; c.lineCap = "round";
                const A = (0.12 + 0.88 * Math.min(1, cu.lv * 1.6)) * (mid - 2) * cv.amp;
                c.beginPath();
                for (let x = 0; x <= w; x += 2) {
                    const t = x / w, env = Math.pow(Math.sin(Math.PI * t), 2);
                    const y = mid + A * env * Math.sin(cu.k * 2 * Math.PI * t + root.phase * cu.sp);
                    x === 0 ? c.moveTo(x, y) : c.lineTo(x, y);
                }
                c.stroke();
            }
        }
    }

    component Ctl: DankIcon {
        property var action
        size: 18
        color: Theme.surfaceText
        opacity: ma.containsMouse ? 1 : 0.6
        MouseArea { id: ma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.action() }
    }

    // El centro de la barra queda vacío hasta que suena música
    onPlayingChanged: playing ? clearVisibilityOverride() : setVisibilityOverride(false)
    Component.onCompleted: if (!playing) setVisibilityOverride(false)

    horizontalBarPill: Component {
        Row {
            spacing: 10
            Ctl { anchors.verticalCenter: parent.verticalCenter; visible: root.playing; size: 16; name: "skip_previous"; action: () => root.player.previous() }
            Waves { anchors.verticalCenter: parent.verticalCenter; visible: root.playing }
            Ctl { anchors.verticalCenter: parent.verticalCenter; visible: root.playing; size: 16; name: "skip_next"; action: () => root.player.next() }
            // En pausa: solo una nota tenue (hover abre el reproductor)
            DankIcon { anchors.verticalCenter: parent.verticalCenter; visible: !root.playing; name: "music_note"; size: 16; color: Theme.surfaceText; opacity: 0.5 }
        }
    }

    popoutWidth: 680
    popoutHeight: 390
    popoutContent: Component {
        PopoutComponent {
            headerText: root.player ? "" : "Sin música"
            detailsText: root.player ? "" : "Pon algo en Spotify, el navegador o cualquier reproductor"

            Item {
                width: parent.width
                height: 350
                visible: !!root.player

                Timer { interval: 250; running: root.playing; repeat: true; onTriggered: root.player?.positionChanged() }

                // Fondo: la misma carátula, muy difuminada y oscura
                Item {
                    anchors.fill: parent
                    clip: true
                    Image {
                        id: bg
                        anchors.fill: parent; anchors.margins: -40
                        source: root.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop; asynchronous: true
                        visible: false
                    }
                    MultiEffect { anchors.fill: bg; source: bg; blurEnabled: true; blur: 1; blurMax: 64; opacity: 0.35; saturation: -0.3 }
                }

                Column {
                    id: izq
                    width: 240
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 4 }
                    spacing: 14

                    Rectangle {
                        width: 180; height: 180; radius: 22
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.withAlpha(Theme.surfaceText, 0.06)
                        Image {
                            id: art
                            anchors.fill: parent
                            source: root.player?.trackArtUrl ?? ""
                            // Miniatura hqdefault de YouTube (480x360): quitar sus franjas negras
                            sourceClipRect: source.toString().includes("ytimg.com") && source.toString().includes("hqdefault") ? Qt.rect(0, 45, 480, 270) : undefined
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                            visible: false
                        }
                        Rectangle { id: artMask; anchors.fill: parent; radius: 22; visible: false; layer.enabled: true }
                        MultiEffect { anchors.fill: art; source: art; maskEnabled: true; maskSource: artMask; visible: art.status === Image.Ready }
                        DankIcon { anchors.centerIn: parent; visible: art.status !== Image.Ready; name: "music_note"; size: 56; color: Theme.surfaceText; opacity: 0.3 }
                    }

                    Column {
                        width: parent.width
                        spacing: 3
                        StyledText { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; wrapMode: Text.NoWrap; maximumLineCount: 1; text: root.player?.trackTitle || "Sin título"; font.pixelSize: 16; font.weight: Font.DemiBold; color: Theme.surfaceText }
                        StyledText { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; wrapMode: Text.NoWrap; maximumLineCount: 1; text: root.player?.trackArtist || root.player?.identity || ""; font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.55 }
                    }


                    // Progreso: clic para saltar a ese punto
                    Column {
                        width: parent.width
                        spacing: 6
                        visible: (root.player?.length ?? 0) > 0
                        Rectangle {
                            width: parent.width; height: 3; radius: 1.5
                            color: Theme.withAlpha(Theme.surfaceText, 0.12)
                            Rectangle { height: parent.height; radius: 1.5; color: Theme.surfaceText; width: parent.width * Math.min(1, (root.player?.position ?? 0) / Math.max(1, root.player?.length ?? 1)) }
                            MouseArea { anchors.fill: parent; anchors.margins: -8; enabled: root.player?.canSeek ?? false; cursorShape: Qt.PointingHandCursor
                                onClicked: m => root.player.position = root.player.length * m.x / width }
                        }
                        Item {
                            width: parent.width; height: 14
                            StyledText { text: root.fmt(root.player?.position); font.pixelSize: 11; font.features: { "tnum": 1 }; color: Theme.surfaceText; opacity: 0.5 }
                            StyledText { anchors.right: parent.right; text: root.fmt(root.player?.length); font.pixelSize: 11; font.features: { "tnum": 1 }; color: Theme.surfaceText; opacity: 0.5 }
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 30
                        Ctl { anchors.verticalCenter: parent.verticalCenter; size: 26; name: "skip_previous"; action: () => root.player.previous() }
                        Rectangle {
                            width: 54; height: 54; radius: 27
                            color: Theme.surfaceText
                            scale: pma.pressed ? 0.94 : 1
                            DankIcon { anchors.centerIn: parent; name: root.playing ? "pause" : "play_arrow"; size: 28; color: Theme.surface }
                            MouseArea { id: pma; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.player.togglePlaying() }
                        }
                        Ctl { anchors.verticalCenter: parent.verticalCenter; size: 26; name: "skip_next"; action: () => root.player.next() }
                    }
                }

                // Letra: la línea actual centrada y resaltada; clic en una línea salta a ese punto
                Item {
                    anchors { left: izq.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 24; rightMargin: 4 }
                    clip: true

                    ListView {
                        id: letra
                        anchors.fill: parent
                        visible: root.lyrics.length > 0
                        model: root.lyrics
                        currentIndex: root.lyricIndex
                        spacing: 10
                        interactive: false
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        preferredHighlightBegin: height / 2 - 20
                        preferredHighlightEnd: height / 2 + 20
                        highlightMoveDuration: 0
                        delegate: StyledText {
                            required property var modelData
                            required property int index
                            width: letra.width
                            wrapMode: Text.WordWrap
                            text: modelData.text
                            font.pixelSize: index === root.lyricIndex ? 18 : 15
                            font.weight: index === root.lyricIndex ? Font.DemiBold : Font.Normal
                            color: Theme.surfaceText
                            opacity: index === root.lyricIndex ? 1 : 0.35
                            MouseArea { anchors.fill: parent; enabled: root.player?.canSeek ?? false; cursorShape: Qt.PointingHandCursor; onClicked: root.player.position = modelData.t }
                        }
                    }

                    // Sin tiempos: texto plano con scroll
                    Flickable {
                        anchors.fill: parent
                        visible: root.lyrics.length === 0 && root.plainLyrics !== ""
                        contentHeight: plano.height
                        StyledText { id: plano; width: parent.width; wrapMode: Text.WordWrap; text: root.plainLyrics; font.pixelSize: 14; lineHeight: 1.3; color: Theme.surfaceText; opacity: 0.8 }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.lyrics.length === 0 && root.plainLyrics === ""
                        text: root.lyricsLoading ? "Buscando letra…" : "Sin letra para esta canción"
                        font.pixelSize: 13; color: Theme.surfaceText; opacity: 0.4
                    }
                }

                // Solo con `musica` (mpv): abrir/ocultar la ventana de letra y quitar la música (cierra mpv)
                Row {
                    anchors { right: parent.right; top: parent.top }
                    visible: root.isMusica
                    spacing: 14
                    Ctl { size: 18; name: "open_in_new"; action: () => ventanaProc.running = true }
                    Ctl { size: 18; name: "close"; action: () => root.player.stop() }
                }
            }
        }
    }

    // En los bordes laterales: ⏮ ondas ⏭ en columna
    verticalBarPill: Component {
        Column {
            spacing: 6
            Ctl { anchors.horizontalCenter: parent.horizontalCenter; visible: root.playing; size: 16; name: "skip_previous"; action: () => root.player.previous() }
            Waves { anchors.horizontalCenter: parent.horizontalCenter; visible: root.playing; width: 24; height: 22 }
            Ctl { anchors.horizontalCenter: parent.horizontalCenter; visible: root.playing; size: 16; name: "skip_next"; action: () => root.player.next() }
            DankIcon { anchors.horizontalCenter: parent.horizontalCenter; visible: !root.playing; name: "music_note"; size: 16; color: Theme.surfaceText; opacity: 0.5 }
        }
    }
}
