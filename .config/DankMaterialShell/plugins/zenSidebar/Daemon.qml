import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Panel lateral del modo zen. Una franja invisible de 3 px en el borde izquierdo lo abre al pasar
// el mouse; ocupa 1/4 de la pantalla de arriba abajo y se cierra al salir (o con Esc).
// Pendientes: tareas locales de DMS por día (~/.config/niri-calendar-todo/tasks.json, las mismas
// del calendario del Resumen). Notas: carpetas y .md reales en ~/Notas; borrar manda a la papelera.
// Listas: checklists en ~/Listas (selector Notas / Listas en la cabecera de la tarjeta).
Item {
    id: root
    property var pluginService: null
    property string pluginId: ""

    property string mode: ""
    FileView { path: Quickshell.env("HOME") + "/.local/state/theme-mode"; watchChanges: true; onFileChanged: reload(); onLoaded: root.mode = text().trim() }
    readonly property bool zen: mode === "zen"

    // dms ipc call zensidebar toggle  (sirve para un atajo de teclado)
    signal toggleRequested
    IpcHandler {
        target: "zensidebar"
        function toggle(): string { root.toggleRequested(); return "ok" }
    }

    readonly property string notesDir: Quickshell.env("HOME") + "/Notas"
    property date today: new Date()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.today = new Date() }

    function key(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function tasksOn(d) { return (CalendarService.localTasks[key(d)] || []) }
    function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }
    readonly property var upcoming: {
        const out = [], tk = key(today), all = CalendarService.localTasks;
        for (const k of Object.keys(all).filter(k => k >= tk).sort())
            for (const t of all[k]) if (!t.completed) out.push({ day: k, id: "task_" + t.id, text: t.text });
        return out;
    }
    function dayLabel(k) {
        const p = k.split("-"), d = new Date(+p[0], +p[1] - 1, +p[2]);
        const diff = Math.round((d - new Date(today.getFullYear(), today.getMonth(), today.getDate())) / 86400000);
        if (diff === 0) return "Hoy";
        if (diff === 1) return "Mañana";
        return cap(Qt.locale("es_ES").toString(d, diff < 7 ? "dddd" : "d MMM"));
    }

    // ---------- Notas: árbol de archivos ----------
    // Cada entrada lleva last (último hijo) y guides (por cada ancestro, si su línea sigue bajando).
    property var entries: []
    property var expanded: ({})
    property string selectedDir: ""
    property string openNote: ""
    property string confirmDelete: ""

    // Colores suaves por rama (carpeta de primer nivel): salvia, arena, niebla, arcilla, lavanda, musgo
    readonly property var palette: ["#9DB8A0", "#CDB892", "#9FB4C7", "#C49A8A", "#ADA3C4", "#A7B68A"]
    function hueOf(e) { return e.hue >= 0 ? palette[e.hue % palette.length] : Theme.surfaceText }

    // Lista ~/Notas: carpetas y .md, con la primera línea de cada nota como vista previa.
    Process {
        id: lister
        command: ["bash", "-c", "cd \"$1\" || exit 0; find . -mindepth 1 -not -path '*/.*' -printf '%y\\t%P\\n' | while IFS=$'\\t' read -r t p; do if [ \"$t\" = d ]; then printf 'd\\t%s\\t\\n' \"$p\"; else case \"$p\" in *.md) l=$(grep -m1 -v '^[[:space:]]*$' \"$p\" | cut -c1-90); printf 'f\\t%s\\t%s\\n' \"$p\" \"$l\";; esac; fi; done", "bash", root.notesDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const kids = {};
                for (const line of text.split("\n")) {
                    if (!line) continue;
                    const [t, p, prev] = line.split("\t");
                    const i = p.lastIndexOf("/"), parent = i < 0 ? "" : p.slice(0, i);
                    (kids[parent] = kids[parent] || []).push({ path: p, name: p.slice(i + 1).replace(/\.md$/, ""), dir: t === "d",
                        preview: (prev || "").replace(/^[#>*\-\s]+/, "") });
                }
                const out = [];
                let topDirs = 0;
                const walk = (parent, guides, hue) => {
                    const list = (kids[parent] || []).sort((a, b) => (b.dir - a.dir) || a.name.localeCompare(b.name));
                    list.forEach((e, n) => {
                        e.depth = guides.length;
                        e.guides = guides;
                        e.last = n === list.length - 1;
                        e.count = e.dir ? (kids[e.path] || []).length : 0;
                        e.hue = parent === "" ? (e.dir ? topDirs++ : -1) : hue;
                        out.push(e);
                        if (e.dir) walk(e.path, guides.concat([!e.last]), e.hue);
                    });
                };
                walk("", [], -1);
                const x = Object.assign({}, root.expanded);
                for (const e of out) if (e.dir && x[e.path] === undefined) x[e.path] = e.depth === 0;   // abiertas solo las ramas principales
                root.expanded = x;
                root.entries = out;
            }
        }
    }
    readonly property int noteCount: entries.filter(e => !e.dir).length
    function refresh() { lister.running = false; lister.running = true; listLister.running = false; listLister.running = true }

    // ---------- Listas: ~/Listas/<nombre>.md con "- [ ] algo" / "- [x] algo" (igual que Obsidian) ----------
    // Las demás líneas del archivo se respetan al guardar.
    readonly property string listsDir: Quickshell.env("HOME") + "/Listas"
    property string section: "notes"   // "notes" | "lists"
    property var lists: []              // {name, done, total}
    property string openList: ""
    property string confirmList: ""
    property var lines: []
    onOpenListChanged: lines = []   // nunca guardar las líneas de otra lista mientras carga la nueva
    // filas visibles: categorías ("## Vestimenta") y elementos con casilla
    // Todo elemento es una compra: sin marcar "Por comprar", marcado "Comprado"
    readonly property var rows: lines.map((l, i) => {
        const h = l.match(/^#{1,6}\s+(.*)$/);
        if (h) return { i: i, text: h[1], heading: true };
        const m = l.match(/^- \[([ xX])\] ?(.*)$/);
        return m ? { i: i, text: m[2], done: m[1] !== " ", heading: false } : null;
    }).filter(x => x)
    property bool big: false   // vista grande: panel a media pantalla y la tarjeta ocupa todo el alto
    readonly property var items: rows.filter(x => !x.heading)
    readonly property int doneCount: items.filter(x => x.done).length
    function listHue(name) { const i = lists.findIndex(l => l.name === name); return palette[Math.max(0, i) % palette.length] }

    Process {
        id: listLister
        command: ["bash", "-c", "mkdir -p \"$1\" && cd \"$1\" && for f in *.md; do [ -e \"$f\" ] || continue; printf '%s\\t%s\\t%s\\n' \"${f%.md}\" \"$(grep -c '^- \\[[xX]\\]' \"$f\")\" \"$(grep -c '^- \\[.\\]' \"$f\")\"; done", "bash", root.listsDir]
        stdout: StdioCollector {
            onStreamFinished: root.lists = text.split("\n").filter(l => l).map(l => { const p = l.split("\t"); return { name: p[0], done: +p[1], total: +p[2] } }).sort((a, b) => a.name.localeCompare(b.name))
        }
    }
    FileView {
        id: listFile
        path: root.openList ? root.listsDir + "/" + root.openList + ".md" : ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.lines = text().split("\n")
    }
    property int confirmItem: -1        // línea del elemento que pide confirmación para quitarse
    property bool confirmClear: false   // "Quitar los comprados" pide confirmación
    onLinesChanged: { confirmItem = -1; confirmClear = false }
    function saveList(ls) { lines = ls; listFile.setText(ls.join("\n")); listLister.running = false; listLister.running = true }
    function toggleItem(i) { const ls = lines.slice(); ls[i] = /^- \[ \]/.test(ls[i]) ? ls[i].replace(/^- \[ \]/, "- [x]") : ls[i].replace(/^- \[[xX]\]/, "- [ ]"); saveList(ls) }
    function addItem(t) {
        t = t.trim(); if (!t) return;
        const ls = lines.slice();
        while (ls.length && ls[ls.length - 1] === "") ls.pop();
        ls.push("- [ ] " + t, "");
        saveList(ls);
    }
    function removeItem(i) { const ls = lines.slice(); ls.splice(i, 1); saveList(ls) }
    function clearDone() { saveList(lines.filter(l => !/^- \[[xX]\]/.test(l))) }
    function createList(name) {
        name = name.trim().replace(/\//g, "-");
        if (!name) return;
        if (!lists.some(l => l.name === name)) { openList = name; saveList([]) }
        else openList = name;
    }
    Component.onCompleted: refresh()

    Process { id: runner; onExited: root.refresh() }
    function run(cmd) { runner.command = cmd; runner.running = true }

    // Árbol grande: se puede "entrar" en una carpeta (zoom, con migas de pan) y buscar por nombre.
    property string zoom: ""
    property string query: ""
    readonly property var visibleEntries: {
        const z = zoom, zd = z ? z.split("/").length : 0;
        const inside = entries.filter(e => !z || e.path.startsWith(z + "/"));
        if (query.trim()) {
            const q = query.trim().toLowerCase();
            return inside.filter(e => e.name.toLowerCase().includes(q)).map(e => {
                const rel = z ? e.path.slice(z.length + 1) : e.path, i = rel.lastIndexOf("/");
                return Object.assign({}, e, { depth: 0, guides: [], last: true, where: i < 0 ? "" : rel.slice(0, i).split("/").join("  ›  ") });
            });
        }
        return inside.filter(e => {
            const parts = e.path.split("/");
            for (let i = zd + 1; i < parts.length; i++)
                if (!expanded[parts.slice(0, i).join("/")]) return false;
            return true;
        }).map(e => zd ? Object.assign({}, e, { depth: e.depth - zd, guides: e.guides.slice(zd) }) : e);
    }
    readonly property bool allOpen: entries.every(e => !e.dir || expanded[e.path])
    function setAll(open) {
        const x = {};
        for (const e of entries) if (e.dir) x[e.path] = open;
        expanded = x;
    }
    function enter(p) {
        const x = Object.assign({}, expanded); x[p] = true; expanded = x;
        zoom = p; query = "";
    }
    function toggleDir(p) {
        const x = Object.assign({}, expanded);
        x[p] = !x[p];
        expanded = x;
    }
    // Crea dentro de `dir` ("" = raíz). La carpeta nueva queda abierta para seguir creando adentro.
    function create(kind, name, dir) {
        if (kind === "list") return createList(name);
        name = name.trim().replace(/\//g, "-");
        if (!name) return;
        const rel = (dir ? dir + "/" : "") + name + (kind === "note" ? ".md" : "");
        const abs = notesDir + "/" + rel;
        const x = Object.assign({}, expanded);
        if (dir) x[dir] = true;
        if (kind === "folder") x[rel] = true;
        expanded = x;
        if (kind === "note") { run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"", "sh", abs]); openNote = rel; }
        else run(["mkdir", "-p", abs]);
    }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: scr
            required property var modelData
            property bool open: false
            property bool anyFocus: false   // hay texto escrito sin enviar en un campo
            property bool armed: false      // el mouse ya entró al panel desde que se abrió
            onOpenChanged: { anyFocus = false; armed = false }
            // El atajo abre solo en el monitor enfocado; cerrar, en cualquiera que lo tenga abierto
            Connections { target: root; function onToggleRequested() {
                if (scr.open) { scr.open = false; return }
                if (scr.modelData.name !== NiriService.currentOutput) return
                root.refresh(); scr.open = true
            } }

            // Borde sensible
            PanelWindow {
                screen: scr.modelData
                visible: root.zen && !scr.open
                anchors { left: true; top: true; bottom: true }
                implicitWidth: 3
                exclusiveZone: 0
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "zen-sidebar-edge"
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: openDelay.restart()
                    onExited: openDelay.stop()
                }
                // Pequeña espera para no abrirlo al pasar de largo
                Timer { id: openDelay; interval: 180; onTriggered: { root.refresh(); scr.open = true } }
            }

            PanelWindow {
                id: panel
                screen: scr.modelData
                visible: root.zen && (scr.open || slide.running)
                anchors { left: true; top: true; bottom: true }
                implicitWidth: Math.round(scr.modelData.width * (root.big ? 0.5 : 0.25))
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "zen-sidebar"
                WlrLayershell.keyboardFocus: scr.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                // Se cierra solo cuando el mouse lleva un rato fuera (y no hay texto a medio escribir)
                Timer {
                    interval: 450
                    running: scr.open && scr.armed && !sheetHover.hovered && !scr.anyFocus
                    onTriggered: scr.open = false
                }

                Item {
                    id: sheet
                    width: parent.width; height: parent.height
                    x: scr.open ? 0 : -width
                    Behavior on x { NumberAnimation { id: slide; duration: 220; easing.type: Easing.OutCubic } }
                    focus: true
                    Keys.onEscapePressed: { scr.anyFocus = false; scr.open = false }

                    HoverHandler { id: sheetHover; onHoveredChanged: if (hovered) scr.armed = true }

                    // Fondo: oscuro, casi opaco, con borde izquierdo finísimo
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.surface
                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.withAlpha(Theme.surfaceText, 0.07) }
                    }

                    SidebarContent { anchors.fill: parent; anchors.margins: 32; anchors.topMargin: 64; scope: scr }
                }
            }
        }
    }

    // ================= Contenido =================
    component SectionTitle: StyledText {
        font.pixelSize: 11; font.letterSpacing: 2.5; font.weight: Font.Medium
        color: Theme.surfaceText; opacity: 0.4
    }
    component IconBtn: DankIcon {
        property var action
        size: 18; color: Theme.surfaceText
        opacity: ib.containsMouse ? 1 : 0.5
        MouseArea { id: ib; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.action() }
    }
    // Agrandar / achicar la vista de notas y listas
    component BigBtn: IconBtn {
        size: 16
        name: root.big ? "close_fullscreen" : "open_in_full"
        action: () => root.big = !root.big
    }
    component Field: DankTextField {
        property var scope
        height: 40
        cornerRadius: 20
        onTextEdited: scope.anyFocus = text.trim() !== ""
        onAccepted: scope.anyFocus = false
    }

    component SidebarContent: Item {
        id: sc
        property var scope
        property date shown: new Date(root.today.getFullYear(), root.today.getMonth(), 1)
        property date selected: root.today
        readonly property bool notesOn: root.section === "notes"

        Column {
            id: top
            visible: !root.big
            width: parent.width
            spacing: 22

            // ---- Encabezado ----
            Column {
                spacing: 2
                StyledText { text: root.cap(Qt.locale("es_ES").toString(root.today, "dddd")); font.pixelSize: 15; color: Theme.surfaceText; opacity: 0.5 }
                StyledText { text: Qt.locale("es_ES").toString(root.today, "d 'de' MMMM"); font.pixelSize: 30; font.weight: Font.Light; color: Theme.surfaceText }
            }

            // ---- Mes ----
            Column {
                width: parent.width
                spacing: 10
                Item {
                    width: parent.width; height: 22
                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: root.cap(Qt.locale("es_ES").toString(sc.shown, "MMMM yyyy")); font.pixelSize: 14; font.weight: Font.Medium; color: Theme.surfaceText; opacity: 0.85 }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 16
                        IconBtn { name: "chevron_left"; action: () => sc.shown = new Date(sc.shown.getFullYear(), sc.shown.getMonth() - 1, 1) }
                        IconBtn { name: "today"; action: () => { sc.shown = new Date(root.today.getFullYear(), root.today.getMonth(), 1); sc.selected = root.today } }
                        IconBtn { name: "chevron_right"; action: () => sc.shown = new Date(sc.shown.getFullYear(), sc.shown.getMonth() + 1, 1) }
                    }
                }
                Grid {
                    id: grid
                    columns: 7
                    width: parent.width
                    readonly property real cell: width / 7
                    Repeater {
                        model: ["L", "M", "M", "J", "V", "S", "D"]
                        StyledText { required property string modelData; width: grid.cell; height: 22; horizontalAlignment: Text.AlignHCenter; text: modelData; font.pixelSize: 11; color: Theme.surfaceText; opacity: 0.35 }
                    }
                    Repeater {
                        model: 42
                        Item {
                            required property int index
                            readonly property date d: { const o = (sc.shown.getDay() + 6) % 7; return new Date(sc.shown.getFullYear(), sc.shown.getMonth(), index - o + 1) }
                            readonly property bool inMonth: d.getMonth() === sc.shown.getMonth()
                            readonly property bool isToday: root.key(d) === root.key(root.today)
                            readonly property bool isSel: root.key(d) === root.key(sc.selected)
                            width: grid.cell; height: 36
                            Rectangle {
                                anchors.centerIn: parent
                                width: 32; height: 32; radius: 16
                                color: isToday ? Theme.surfaceText : (dma.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.07) : "transparent")
                                border.width: isSel && !isToday ? 1 : 0
                                border.color: Theme.withAlpha(Theme.surfaceText, 0.3)
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: d.getDate()
                                font.pixelSize: 13; font.features: { "tnum": 1 }
                                font.weight: isToday ? Font.DemiBold : Font.Normal
                                color: isToday ? Theme.surface : Theme.surfaceText
                                opacity: inMonth ? 0.9 : 0.2
                            }
                            Rectangle {
                                visible: root.tasksOn(d).length > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: 4; height: 4; radius: 2
                                color: Theme.surfaceText; opacity: 0.6
                            }
                            MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { sc.selected = parent.d; addField.forceActiveFocus() } }
                        }
                    }
                }
            }

            Field {
                id: addField
                scope: sc.scope
                width: parent.width
                leftIconName: "add"
                placeholderText: "Agregar a " + root.dayLabel(root.key(sc.selected)).toLowerCase() + "…"
                onAccepted: { if (text.trim()) CalendarService.addTaskForDate(sc.selected, text.trim()); text = "" }
            }

            // ---- Próximo ----
            Column {
                width: parent.width
                spacing: 4
                SectionTitle { text: "PRÓXIMO"; bottomPadding: 6 }
                StyledText { visible: root.upcoming.length === 0; text: "Nada pendiente. Disfruta la calma."; font.pixelSize: 13; color: Theme.surfaceText; opacity: 0.4 }
                Repeater {
                    model: root.upcoming.slice(0, 5)
                    Item {
                        required property var modelData
                        width: parent.width; height: 32
                        Rectangle { anchors.fill: parent; radius: 12; color: uma.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.05) : "transparent" }
                        MouseArea { id: uma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8
                            spacing: 12
                            IconBtn { anchors.verticalCenter: parent.verticalCenter; name: "radio_button_unchecked"; size: 17; action: () => CalendarService.toggleTask(modelData.id) }
                            StyledText { anchors.verticalCenter: parent.verticalCenter; width: 70; text: root.dayLabel(modelData.day); font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.45 }
                            StyledText { anchors.verticalCenter: parent.verticalCenter; width: sc.width - 150; elide: Text.ElideRight; text: modelData.text; font.pixelSize: 14; color: Theme.surfaceText }
                        }
                        IconBtn { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; visible: uma.containsMouse; name: "close"; size: 16; action: () => CalendarService.removeTask(modelData.id) }
                    }
                }
            }

        }

        // ---- Notas: todo dentro de una tarjeta ----
        Rectangle {
            id: notesCard
            anchors.top: root.big ? parent.top : top.bottom; anchors.topMargin: root.big ? 0 : 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: parent.width
            radius: 24
            color: Theme.withAlpha(Theme.surfaceText, 0.025)
            border.width: 1; border.color: Theme.withAlpha(Theme.surfaceText, 0.05)
        }

        Item {
            id: notesHead
            visible: sc.notesOn ? root.openNote === "" : root.openList === ""
            anchors.top: notesCard.top; anchors.topMargin: 16
            anchors.left: notesCard.left; anchors.leftMargin: 18
            anchors.right: notesCard.right; anchors.rightMargin: 14
            height: 30
            // Notas / Listas: la sección activa en claro, la otra apagada; clic para cambiar
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Repeater {
                    model: [{ id: "notes", label: "Notas" }, { id: "lists", label: "Listas" }]
                    StyledText {
                        required property var modelData
                        readonly property bool on: root.section === modelData.id
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        font.pixelSize: 16; font.weight: on ? Font.Medium : Font.Normal
                        color: Theme.surfaceText
                        opacity: on ? 1 : (sma.containsMouse ? 0.6 : 0.3)
                        MouseArea { id: sma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.section = parent.modelData.id; newField.visible = false } }
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sc.notesOn ? root.noteCount + (root.noteCount === 1 ? " hoja" : " hojas") : root.lists.length + (root.lists.length === 1 ? " lista" : " listas")
                    font.pixelSize: 11; color: Theme.surfaceText; opacity: 0.4
                }
            }
            // Herramientas en una cápsula
            Rectangle {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: tools.implicitWidth + 24; height: 30; radius: 15
                color: Theme.withAlpha(Theme.surfaceText, 0.04)
                Row {
                    id: tools
                    anchors.centerIn: parent
                    spacing: 14
                    IconBtn { visible: sc.notesOn; size: 16; name: "search"; opacity: searchField.visible ? 1 : 0.5; action: () => { searchField.visible = !searchField.visible; if (searchField.visible) searchField.forceActiveFocus(); else { searchField.text = ""; root.query = "" } } }
                    IconBtn { visible: sc.notesOn; size: 16; name: root.allOpen ? "unfold_less" : "unfold_more"; action: () => root.setAll(!root.allOpen) }
                    IconBtn { visible: sc.notesOn; size: 16; name: "create_new_folder"; action: () => newField.ask("folder", root.zoom) }
                    IconBtn { visible: sc.notesOn; size: 16; name: "note_add"; action: () => newField.ask("note", root.zoom) }
                    IconBtn { visible: !sc.notesOn; size: 16; name: "playlist_add"; action: () => newField.ask("list", "") }
                    BigBtn {}
                }
            }
        }

        Column {
            id: navBox
            visible: sc.notesOn && root.openNote === ""
            anchors.top: notesHead.bottom; anchors.topMargin: 10
            anchors.left: notesCard.left; anchors.leftMargin: 14
            anchors.right: notesCard.right; anchors.rightMargin: 14
            spacing: 10

            DankTextField {
                id: searchField
                visible: false
                width: parent.width; height: 38
                cornerRadius: 19
                leftIconName: "search"
                placeholderText: "Buscar notas y carpetas" + (root.zoom ? " en " + root.zoom.split("/").pop() : "")
                onTextEdited: root.query = text
            }

            // Migas de pan: Notas › Universidad › Proyectos (clic para subir)
            Flow {
                visible: root.zoom !== ""
                width: parent.width
                spacing: 4
                Repeater {
                    model: [""].concat(root.zoom ? root.zoom.split("/").map((_, i, a) => a.slice(0, i + 1).join("/")) : [])
                    Row {
                        required property string modelData
                        required property int index
                        spacing: 4
                        StyledText { visible: index > 0; anchors.verticalCenter: parent.verticalCenter; text: "›"; font.pixelSize: 13; color: Theme.surfaceText; opacity: 0.3 }
                        Rectangle {
                            readonly property bool current: modelData === root.zoom
                            width: crumb.implicitWidth + 16; height: 26; radius: 13
                            color: current ? Theme.withAlpha(Theme.surfaceText, 0.09) : (cm.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.05) : "transparent")
                            Row {
                                id: crumb
                                anchors.centerIn: parent
                                spacing: 5
                                DankIcon { visible: index === 0; anchors.verticalCenter: parent.verticalCenter; name: "home"; size: 14; color: Theme.surfaceText; opacity: 0.7 }
                                StyledText { anchors.verticalCenter: parent.verticalCenter; text: index === 0 ? "Notas" : modelData.split("/").pop(); font.pixelSize: 12; font.weight: parent.parent.current ? Font.Medium : Font.Normal; color: Theme.surfaceText; opacity: parent.parent.current ? 1 : 0.6 }
                            }
                            MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.zoom = modelData }
                        }
                    }
                }
            }
        }

        Field {
            id: newField
            property string kind: "note"
            property string dir: ""
            function ask(k, d) { kind = k; dir = d; root.selectedDir = d; text = ""; visible = true; forceActiveFocus() }
            scope: sc.scope
            visible: false
            anchors.top: navBox.visible && navBox.height > 0 ? navBox.bottom : notesHead.bottom; anchors.topMargin: 10
            anchors.left: notesCard.left; anchors.leftMargin: 14
            anchors.right: notesCard.right; anchors.rightMargin: 14
            leftIconName: kind === "note" ? "description" : kind === "list" ? "checklist" : "folder"
            placeholderText: (kind === "note" ? "Nueva nota" : kind === "list" ? "Nueva lista" : "Nueva carpeta") + (dir ? " en " + dir.split("/").pop() : "") + "  ·  Enter para crear"
            onAccepted: { root.create(kind, text, dir); text = ""; visible = false; root.selectedDir = "" }
            onFocusStateChanged: f => { if (!f) { text = ""; visible = false; root.selectedDir = ""; sc.scope.anyFocus = false } }
        }

        // ---- Árbol real ----
        // La carpeta raíz (Notas o la carpeta en la que entraste) arriba al centro; sus hijos cuelgan
        // debajo, repartidos a lo ancho, y así hacia abajo. Cada subárbol ocupa el ancho de sus hijos y
        // el padre queda centrado sobre ellos. Si no cabe, se arrastra para recorrerlo.
        // Clic en carpeta: abrir/cerrar · doble clic: entrar · clic en hoja: abrir la nota.
        Item {
            id: treeArea
            visible: sc.notesOn && root.openNote === ""
            anchors.top: newField.visible ? newField.bottom : navBox.height > 0 ? navBox.bottom : notesHead.bottom
            anchors.topMargin: 8
            anchors.bottom: notesCard.bottom; anchors.bottomMargin: 10
            anchors.left: notesCard.left; anchors.leftMargin: 6
            anchors.right: notesCard.right; anchors.rightMargin: 6
            clip: true
            readonly property bool searching: root.query.trim() !== ""

            readonly property int nodeW: 84
            readonly property int gap: 6
            readonly property int levelH: 96
            readonly property int padTop: 30

            // nodos: {e, path, x, y, parent, open, depth}
            readonly property var layout: {
                const W = nodeW, G = gap, L = levelH, z = root.zoom, ex = root.expanded;
                const kids = {};
                for (const e of root.entries) {
                    const i = e.path.lastIndexOf("/"), par = i < 0 ? "" : e.path.slice(0, i);
                    (kids[par] = kids[par] || []).push(e);
                }
                const memo = {};
                const isOpen = (e, path) => path === z || (e && e.dir && ex[path]);
                const width = (e, path) => {
                    if (memo[path] !== undefined) return memo[path];
                    const ch = isOpen(e, path) ? (kids[path] || []) : [];
                    const w = ch.length ? Math.max(W, ch.reduce((s, c) => s + width(c, c.path), 0) + G * (ch.length - 1)) : W;
                    return memo[path] = w;
                };
                const nodes = [];
                let maxDepth = 0;
                const place = (e, path, depth, left, parent) => {
                    const w = width(e, path), open = isOpen(e, path), idx = nodes.length;
                    nodes.push({ e: e, path: path, x: left + w / 2, y: padTop + depth * L, parent: parent, open: open, depth: depth });
                    maxDepth = Math.max(maxDepth, depth);
                    if (!open) return;
                    const ch = kids[path] || [];
                    const cw = ch.reduce((s, c) => s + width(c, c.path), 0) + G * Math.max(0, ch.length - 1);
                    let x = left + (w - cw) / 2;
                    for (const c of ch) { place(c, c.path, depth + 1, x, idx); x += width(c, c.path) + G; }
                };
                const rootEntry = z ? root.entries.find(e => e.path === z) || null : null;
                place(rootEntry, z, 0, 0, -1);
                return { nodes: nodes, width: width(rootEntry, z), height: padTop + (maxDepth + 1) * L };
            }

            Flickable {
                id: flick
                anchors.fill: parent
                visible: !treeArea.searching
                contentWidth: Math.max(width, treeArea.layout.width + 24)
                contentHeight: Math.max(height, treeArea.layout.height + 10)
                boundsBehavior: Flickable.StopAtBounds
                readonly property real ox: (contentWidth - treeArea.layout.width) / 2
                onContentWidthChanged: contentX = Math.max(0, (contentWidth - width) / 2)

                // tallos: curvas suaves de cada padre a cada hijo
                Canvas {
                    id: stems
                    width: flick.contentWidth; height: flick.contentHeight
                    property var deps: [treeArea.layout, flick.ox]
                    onDepsChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d"), ns = treeArea.layout.nodes, ox = flick.ox;
                        c.reset();
                        c.lineCap = "round";
                        for (const n of ns) {
                            if (n.parent < 0) continue;
                            const p = ns[n.parent], hc = root.hueOf(n.e);
                            const x1 = ox + p.x, y1 = p.y + 58, x2 = ox + n.x, y2 = n.y - 2;
                            c.strokeStyle = p.depth === 0 && !root.zoom ? Qt.rgba(0.62, 0.78, 0.64, 0.35) : Qt.rgba(hc.r, hc.g, hc.b, 0.4);
                            c.lineWidth = Math.max(1.2, 2.4 - n.depth * 0.35);
                            c.beginPath();
                            c.moveTo(x1, y1);
                            c.bezierCurveTo(x1, y1 + 22, x2, y2 - 22, x2, y2);
                            c.stroke();
                        }
                    }
                }

                Repeater {
                    model: treeArea.layout.nodes
                    Item {
                        id: node
                        required property var modelData
                        readonly property var n: modelData
                        readonly property var e: n.e
                        readonly property bool isRoot: n.parent < 0
                        readonly property bool isDir: isRoot || e.dir
                        readonly property color hue: isRoot && !root.zoom ? "#9DB8A0" : root.hueOf(e)
                        readonly property bool active: !isDir && root.openNote === e.path
                        readonly property bool hot: nma.containsMouse || acts.hovered
                        // la cápsula de acciones espera un momento antes de irse, para poder llegar a ella
                        property bool keep: false
                        onHotChanged: if (hot) { keep = true; hideActs.stop() } else hideActs.restart()
                        Timer { id: hideActs; interval: 400; onTriggered: node.keep = false }
                        x: flick.ox + n.x - treeArea.nodeW / 2
                        y: n.y
                        width: treeArea.nodeW; height: 70
                        z: keep ? 3 : 1

                        // círculo de carpeta / hoja de nota
                        Rectangle {
                            visible: node.isDir
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: node.isRoot ? 40 : 34; height: width; radius: width / 2
                            color: Qt.rgba(node.hue.r, node.hue.g, node.hue.b, node.n.open ? 0.24 : 0.09)
                            border.width: node.hot ? 1.5 : 1
                            border.color: Qt.rgba(node.hue.r, node.hue.g, node.hue.b, node.n.open ? 0.75 : 0.45)
                            DankIcon {
                                anchors.centerIn: parent
                                name: node.isRoot ? (root.zoom ? "park" : "psychiatry") : node.n.open ? "folder_open" : "folder"
                                filled: true; size: node.isRoot ? 20 : 16; color: node.hue
                            }
                            // burbuja con cuántos hay adentro si está cerrada
                            Rectangle {
                                visible: !node.isRoot && !node.n.open && node.e.count > 0
                                anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -6; anchors.topMargin: -4
                                width: Math.max(16, cnt.implicitWidth + 8); height: 16; radius: 8
                                color: Theme.surfaceContainerHigh
                                border.width: 1; border.color: Qt.rgba(node.hue.r, node.hue.g, node.hue.b, 0.6)
                                StyledText { id: cnt; anchors.centerIn: parent; text: node.isRoot ? "" : node.e.count; font.pixelSize: 9; font.weight: Font.Medium; color: node.hue }
                            }
                        }
                        Canvas {
                            visible: !node.isDir
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            width: 26; height: 26
                            property var deps: [node.hue, node.active, node.hot]
                            onDepsChanged: requestPaint()
                            onPaint: {
                                const c = getContext("2d"), hc = node.hue;
                                c.reset();
                                c.save(); c.translate(13, 13); c.rotate(-Math.PI / 4);
                                c.fillStyle = Qt.rgba(hc.r, hc.g, hc.b, node.active ? 0.95 : node.hot ? 0.8 : 0.6);
                                c.beginPath(); c.moveTo(0, 12); c.quadraticCurveTo(-10, 0, 0, -12); c.quadraticCurveTo(10, 0, 0, 12); c.fill();
                                c.strokeStyle = Theme.withAlpha(Theme.surface, 0.6); c.lineWidth = 1;
                                c.beginPath(); c.moveTo(0, 11); c.lineTo(0, -9); c.stroke();
                                c.restore();
                            }
                        }

                        StyledText {
                            y: node.isRoot ? 44 : 38
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                            text: node.isRoot ? (root.zoom ? root.zoom.split("/").pop() : "Notas") : node.e.name
                            font.pixelSize: node.isRoot ? 13 : 12
                            font.weight: node.isDir ? Font.DemiBold : node.active ? Font.Medium : Font.Normal
                            color: Theme.surfaceText
                            opacity: node.isDir || node.active ? 0.95 : 0.75
                        }

                        MouseArea {
                            id: nma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (node.isRoot) return;
                                if (node.e.dir) root.toggleDir(node.e.path); else root.openNote = node.e.path;
                            }
                            onDoubleClicked: if (!node.isRoot && node.e.dir) root.enter(node.e.path)
                        }

                        // acciones flotantes encima del nodo
                        Rectangle {
                            id: acts
                            property bool hovered: ah.hovered
                            HoverHandler { id: ah }
                            readonly property string target: node.isRoot ? root.zoom : node.e.path
                            readonly property bool asking: !node.isRoot && root.confirmDelete === node.e.path
                            visible: node.keep || asking
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: -26
                            width: actRow.implicitWidth + 16; height: 24; radius: 12
                            color: asking ? Qt.rgba(0.35, 0.14, 0.14, 1) : Theme.surfaceContainerHigh
                            border.width: 1; border.color: Theme.withAlpha(Theme.surfaceText, 0.08)
                            Row {
                                id: actRow
                                anchors.centerIn: parent
                                spacing: 10
                                IconBtn { anchors.verticalCenter: parent.verticalCenter; visible: !node.isRoot && node.e.dir && !acts.asking; name: "zoom_in"; size: 14; action: () => root.enter(node.e.path) }
                                IconBtn { anchors.verticalCenter: parent.verticalCenter; visible: node.isRoot && root.zoom !== ""; name: "arrow_upward"; size: 14; action: () => { const i = root.zoom.lastIndexOf("/"); root.zoom = i < 0 ? "" : root.zoom.slice(0, i) } }
                                IconBtn { anchors.verticalCenter: parent.verticalCenter; visible: node.isDir && !acts.asking; name: "note_add"; size: 14; action: () => newField.ask("note", acts.target) }
                                IconBtn { anchors.verticalCenter: parent.verticalCenter; visible: node.isDir && !acts.asking; name: "create_new_folder"; size: 14; action: () => newField.ask("folder", acts.target) }
                                StyledText { anchors.verticalCenter: parent.verticalCenter; visible: acts.asking; text: "¿Borrar?"; font.pixelSize: 11; color: Theme.surfaceText }
                                DankIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !node.isRoot
                                    name: "delete"; size: 14; color: Theme.surfaceText; opacity: dmx.containsMouse || acts.asking ? 0.95 : 0.5
                                    MouseArea {
                                        id: dmx; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!acts.asking) { root.confirmDelete = node.e.path; return; }
                                            root.confirmDelete = "";
                                            if (root.openNote.startsWith(node.e.path)) root.openNote = "";
                                            root.run(["gio", "trash", root.notesDir + "/" + node.e.path]);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // desvanecido a los lados cuando hay más árbol fuera de la vista
            Rectangle {
                visible: flick.visible && flick.contentX > 2
                width: 28; height: parent.height
                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Theme.surface } GradientStop { position: 1; color: Theme.withAlpha(Theme.surface, 0) } }
            }
            Rectangle {
                visible: flick.visible && flick.contentX < flick.contentWidth - flick.width - 2
                anchors.right: parent.right
                width: 28; height: parent.height
                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Theme.withAlpha(Theme.surface, 0) } GradientStop { position: 1; color: Theme.surface } }
            }

            StyledText {
                visible: !treeArea.searching && treeArea.layout.nodes.length <= 1
                anchors.horizontalCenter: parent.horizontalCenter
                y: 112
                horizontalAlignment: Text.AlignHCenter
                width: parent.width - 40
                wrapMode: Text.Wrap
                text: root.zoom ? "Rama vacía: pasa el mouse sobre la carpeta y brota algo con 📄+ o 📁+" : "Tu árbol está por brotar: crea una carpeta o una nota arriba"
                font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.4
            }

            // Búsqueda: lista simple de coincidencias con su ruta
            ListView {
                anchors.fill: parent
                visible: treeArea.searching
                clip: true
                model: root.visibleEntries
                StyledText {
                    visible: parent.count === 0
                    anchors.horizontalCenter: parent.horizontalCenter; y: 16
                    text: "Nada coincide con “" + root.query.trim() + "”"
                    font.pixelSize: 13; color: Theme.surfaceText; opacity: 0.4
                }
                delegate: Item {
                    id: hit
                    required property var modelData
                    width: ListView.view.width; height: 46
                    readonly property color hue: root.hueOf(modelData)
                    Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 14; color: hm.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.05) : "transparent" }
                    Rectangle {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26; radius: 13
                        color: Qt.rgba(hit.hue.r, hit.hue.g, hit.hue.b, 0.14)
                        DankIcon { anchors.centerIn: parent; name: hit.modelData.dir ? "folder" : "eco"; filled: true; size: 14; color: hit.hue }
                    }
                    Column {
                        x: 52; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 66
                        StyledText { width: parent.width; elide: Text.ElideRight; text: hit.modelData.name; font.pixelSize: 14; font.weight: hit.modelData.dir ? Font.DemiBold : Font.Normal; color: Theme.surfaceText }
                        StyledText { width: parent.width; elide: Text.ElideRight; visible: !!hit.modelData.where; text: hit.modelData.where || ""; font.pixelSize: 11; color: Theme.surfaceText; opacity: 0.4 }
                    }
                    MouseArea {
                        id: hm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (hit.modelData.dir) root.enter(hit.modelData.path); else root.openNote = hit.modelData.path; }
                    }
                }
            }
        }

        // ---- Nota abierta: ocupa la tarjeta como una hoja limpia (se guarda sola) ----
        Item {
            id: editorBox
            visible: sc.notesOn && root.openNote !== ""
            anchors.fill: notesCard
            anchors.margins: 20

            readonly property var entry: root.entries.find(e => e.path === root.openNote) || null
            readonly property color hue: entry ? root.hueOf(entry) : Theme.surfaceText
            readonly property int words: editor.text.trim() ? editor.text.trim().split(/\s+/).length : 0

            FileView {
                id: noteFile
                path: root.openNote ? root.notesDir + "/" + root.openNote : ""
                printErrors: false
                onLoaded: { editor.text = text(); saveTimer.stop(); editor.cursorPosition = editor.text.length }
            }
            Timer { id: saveTimer; interval: 600; onTriggered: { noteFile.setText(editor.text); previewTimer.restart() } }
            Timer { id: previewTimer; interval: 400; onTriggered: root.refresh() }
            function close() {
                if (saveTimer.running) { saveTimer.stop(); noteFile.setText(editor.text); root.refresh() }
                root.openNote = "";
            }

            // barra superior: volver · ruta
            Item {
                id: edBar
                width: parent.width; height: 28
                Rectangle {
                    width: backRow.implicitWidth + 20; height: 28; radius: 14
                    color: bma.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.08) : Theme.withAlpha(Theme.surfaceText, 0.04)
                    Row {
                        id: backRow
                        anchors.centerIn: parent
                        spacing: 6
                        DankIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow_back"; size: 15; color: Theme.surfaceText; opacity: 0.75 }
                        StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Árbol"; font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.75 }
                    }
                    MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: editorBox.close() }
                }
                BigBtn { id: edBig; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
                StyledText {
                    anchors.right: edBig.left; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 150
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: { const parts = root.openNote.split("/"); parts.pop(); return parts.length ? parts.join("  ›  ") : "Notas" }
                    font.pixelSize: 11; color: Theme.surfaceText; opacity: 0.4
                }
            }

            // título con su hoja
            Row {
                id: edTitle
                anchors.top: edBar.bottom; anchors.topMargin: 22
                spacing: 12
                Canvas {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22
                    property color hc: editorBox.hue
                    onHcChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        c.save(); c.translate(11, 11); c.rotate(-Math.PI / 4);
                        c.fillStyle = Qt.rgba(hc.r, hc.g, hc.b, 0.85);
                        c.beginPath(); c.moveTo(0, 10); c.quadraticCurveTo(-8.5, 0, 0, -10); c.quadraticCurveTo(8.5, 0, 0, 10); c.fill();
                        c.restore();
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: editorBox.width - 40
                    elide: Text.ElideRight
                    text: root.openNote.replace(/\.md$/, "").split("/").pop()
                    font.pixelSize: 22; font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }
            Rectangle {
                id: edRule
                anchors.top: edTitle.bottom; anchors.topMargin: 16
                width: 40; height: 2; radius: 1
                color: editorBox.hue; opacity: 0.6
            }

            // texto
            Flickable {
                id: edFlick
                anchors.top: edRule.bottom; anchors.topMargin: 18
                anchors.bottom: edFoot.top; anchors.bottomMargin: 12
                width: parent.width
                contentHeight: editor.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                function ensureVisible(r) {
                    if (contentY >= r.y) contentY = r.y;
                    else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
                }
                TextEdit {
                    id: editor
                    width: edFlick.width
                    wrapMode: TextEdit.Wrap
                    color: Theme.surfaceText
                    selectionColor: Theme.withAlpha(editorBox.hue, 0.35)
                    selectedTextColor: Theme.surfaceText
                    font.pixelSize: root.big ? 17 : 15
                    font.family: Theme.fontFamily
                    textFormat: TextEdit.PlainText
                    onTextChanged: if (activeFocus) saveTimer.restart()
                    onCursorRectangleChanged: edFlick.ensureVisible(cursorRectangle)
                    Keys.onEscapePressed: editorBox.close()
                    StyledText { visible: !parent.text; text: "Escribe con calma…"; font.pixelSize: 15; color: Theme.surfaceText; opacity: 0.3 }
                }
                MouseArea { anchors.fill: parent; z: -1; onClicked: { editor.forceActiveFocus(); editor.cursorPosition = editor.text.length } }
            }

            // pie: palabras · guardado
            Item {
                id: edFoot
                anchors.bottom: parent.bottom
                width: parent.width; height: 18
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: editorBox.words + (editorBox.words === 1 ? " palabra" : " palabras")
                    font.pixelSize: 11; color: Theme.surfaceText; opacity: 0.4
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    DankIcon { anchors.verticalCenter: parent.verticalCenter; name: saveTimer.running ? "edit" : "check"; size: 13; color: saveTimer.running ? Theme.surfaceText : editorBox.hue; opacity: 0.7 }
                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: saveTimer.running ? "Escribiendo…" : "Guardado"; font.pixelSize: 11; color: Theme.surfaceText; opacity: 0.45 }
                }
            }
        }

        // ---- Listas: índice (anillo de avance · nombre · hechas de total) ----
        ListView {
            id: listIndex
            visible: !sc.notesOn && root.openList === ""
            anchors.top: newField.visible ? newField.bottom : notesHead.bottom; anchors.topMargin: 8
            anchors.bottom: notesCard.bottom; anchors.bottomMargin: 10
            anchors.left: notesCard.left; anchors.leftMargin: 8
            anchors.right: notesCard.right; anchors.rightMargin: 8
            clip: true
            model: root.lists
            StyledText {
                visible: parent.count === 0
                anchors.horizontalCenter: parent.horizontalCenter; y: 24
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: "Todavía no hay listas. Crea una con el botón de arriba a la derecha."
                font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.4
            }
            delegate: Item {
                id: lrow
                required property var modelData
                readonly property color hue: root.listHue(modelData.name)
                readonly property bool asking: root.confirmList === modelData.name
                readonly property bool hot: lh.hovered || asking
                width: ListView.view.width; height: 50
                HoverHandler { id: lh }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 2; radius: 16
                    color: lrow.asking ? Qt.rgba(0.35, 0.14, 0.14, 0.6) : lh.hovered ? Theme.withAlpha(Theme.surfaceText, 0.05) : "transparent"
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.confirmList = ""; root.openList = lrow.modelData.name } }
                Ring {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    hue: lrow.hue
                    ratio: lrow.modelData.total ? lrow.modelData.done / lrow.modelData.total : 0
                    DankIcon { visible: lrow.modelData.total > 0 && lrow.modelData.done === lrow.modelData.total; anchors.centerIn: parent; name: "check"; size: 13; color: lrow.hue }
                }
                StyledText {
                    x: 52; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 120; elide: Text.ElideRight
                    text: lrow.asking ? "¿Borrar " + lrow.modelData.name + "?" : lrow.modelData.name
                    font.pixelSize: 14; color: Theme.surfaceText
                }
                StyledText {
                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                    visible: !lrow.hot
                    text: lrow.modelData.total ? lrow.modelData.done + " de " + lrow.modelData.total : "vacía"
                    font.pixelSize: 11; font.features: { "tnum": 1 }
                    color: Theme.surfaceText; opacity: 0.4
                }
                IconBtn {
                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                    visible: lrow.hot
                    name: "delete"; size: 16
                    action: () => {
                        if (!lrow.asking) { root.confirmList = lrow.modelData.name; return; }
                        root.confirmList = "";
                        root.run(["gio", "trash", root.listsDir + "/" + lrow.modelData.name + ".md"]);
                    }
                }
            }
        }

        // ---- Lista abierta: la regla bajo el título es la barra de avance ----
        Item {
            id: listBox
            visible: !sc.notesOn && root.openList !== ""
            anchors.fill: notesCard
            anchors.margins: 20
            readonly property color hue: root.listHue(root.openList)
            readonly property real ratio: root.items.length ? root.doneCount / root.items.length : 0

            Rectangle {
                id: lback
                width: lbRow.implicitWidth + 20; height: 28; radius: 14
                color: lbm.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.08) : Theme.withAlpha(Theme.surfaceText, 0.04)
                Row {
                    id: lbRow
                    anchors.centerIn: parent
                    spacing: 6
                    DankIcon { anchors.verticalCenter: parent.verticalCenter; name: "arrow_back"; size: 15; color: Theme.surfaceText; opacity: 0.75 }
                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Listas"; font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.75 }
                }
                MouseArea { id: lbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openList = "" }
            }
            BigBtn { anchors.right: parent.right; anchors.verticalCenter: lback.verticalCenter }

            StyledText {
                id: lTitle
                anchors.top: lback.bottom; anchors.topMargin: 22
                width: parent.width; elide: Text.ElideRight
                text: root.openList
                font.pixelSize: 22; font.weight: Font.Medium
                color: Theme.surfaceText
            }
            Rectangle {
                id: lbar
                anchors.top: lTitle.bottom; anchors.topMargin: 16
                width: parent.width; height: 3; radius: 1.5
                color: Qt.rgba(listBox.hue.r, listBox.hue.g, listBox.hue.b, 0.14)
                Rectangle { width: Math.max(height, parent.width * listBox.ratio); visible: listBox.ratio > 0; height: parent.height; radius: 1.5; color: listBox.hue; opacity: 0.85 }
            }

            ListView {
                id: itemsView
                anchors.top: lbar.bottom; anchors.topMargin: 14
                anchors.bottom: addItemField.top; anchors.bottomMargin: 10
                width: parent.width
                clip: true
                spacing: 2
                model: root.rows
                StyledText {
                    visible: parent.count === 0
                    y: 8; width: parent.width; wrapMode: Text.Wrap
                    text: "Lista vacía. Escribe abajo para agregar el primer elemento."
                    font.pixelSize: 13; color: Theme.surfaceText; opacity: 0.4
                }
                delegate: Item {
                    id: it
                    required property var modelData
                    readonly property bool cat: modelData.heading
                    // de una categoría: sus elementos hasta la siguiente categoría
                    readonly property var mine: { if (!cat) return []; const out = []; let on = false; for (const x of root.rows) { if (x.heading) on = x.i === modelData.i; else if (on) out.push(x); } return out }
                    width: ListView.view.width
                    height: cat ? 40 : Math.max(38, itText.implicitHeight + 16)
                    HoverHandler { id: ih }
                    // categoría: subtítulo del color de la lista con su avance a la derecha
                    StyledText { visible: it.cat; x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; text: it.modelData.text; font.pixelSize: 13; font.weight: Font.DemiBold; color: listBox.hue }
                    StyledText {
                        visible: it.cat
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                        text: it.mine.filter(x => x.done).length + " de " + it.mine.length + " comprados"
                        font.pixelSize: 11; font.features: { "tnum": 1 }; color: Theme.surfaceText; opacity: 0.35
                    }
                    readonly property bool asking: !cat && root.confirmItem === modelData.i
                    Rectangle { visible: !it.cat; anchors.fill: parent; radius: 12; color: it.asking ? Qt.rgba(0.35, 0.14, 0.14, 0.6) : ih.hovered ? Theme.withAlpha(Theme.surfaceText, 0.05) : "transparent" }
                    // clic en la fila: marca/desmarca; si estaba preguntando "¿Quitar?", solo cancela
                    MouseArea { enabled: !it.cat; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (it.asking) root.confirmItem = -1; else root.toggleItem(it.modelData.i) } }
                    // casilla: aro del color de la lista; marcada, se rellena con ✓
                    Rectangle {
                        visible: !it.cat
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 10
                        color: it.modelData.done ? listBox.hue : "transparent"
                        border.width: it.modelData.done ? 0 : 1.5
                        border.color: Qt.rgba(listBox.hue.r, listBox.hue.g, listBox.hue.b, ih.hovered ? 0.9 : 0.55)
                        DankIcon { visible: !!it.modelData.done; anchors.centerIn: parent; name: "check"; size: 14; color: Theme.surface }
                    }
                    StyledText {
                        id: itText
                        visible: !it.cat
                        x: 40; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 150
                        wrapMode: Text.Wrap
                        text: it.modelData.text
                        font.pixelSize: root.big ? 16 : 14; font.strikeout: !!it.modelData.done
                        color: Theme.surfaceText
                        opacity: it.modelData.done ? 0.35 : 0.95
                    }
                    // compras: etiqueta de estado (la ✕ la reemplaza al pasar el mouse)
                    Rectangle {
                        visible: !it.cat && !ih.hovered && !it.asking
                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        width: tag.implicitWidth + 16; height: 22; radius: 11
                        color: it.modelData.done ? Qt.rgba(listBox.hue.r, listBox.hue.g, listBox.hue.b, 0.18) : "transparent"
                        border.width: it.modelData.done ? 0 : 1
                        border.color: Theme.withAlpha(Theme.surfaceText, 0.15)
                        StyledText {
                            id: tag
                            anchors.centerIn: parent
                            text: it.modelData.done ? "Comprado" : "Por comprar"
                            font.pixelSize: 11
                            color: it.modelData.done ? listBox.hue : Theme.surfaceText
                            opacity: it.modelData.done ? 1 : 0.5
                        }
                    }
                    // ✕ pide confirmación: primer clic pregunta, segundo quita
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        visible: !it.cat && (ih.hovered || it.asking)
                        spacing: 8
                        StyledText { visible: it.asking; anchors.verticalCenter: parent.verticalCenter; text: "¿Quitar?"; font.pixelSize: 11; color: Theme.surfaceText }
                        IconBtn {
                            anchors.verticalCenter: parent.verticalCenter
                            name: it.asking ? "delete" : "close"; size: 15
                            action: () => { if (it.asking) root.removeItem(it.modelData.i); else root.confirmItem = it.modelData.i }
                        }
                    }
                }
            }

            Field {
                id: addItemField
                scope: sc.scope
                anchors.bottom: lfoot.top; anchors.bottomMargin: 12
                width: parent.width
                leftIconName: "add"
                placeholderText: "Agregar a " + root.openList + "…"
                onAccepted: { root.addItem(text); text = ""; scope.anyFocus = false; itemsView.positionViewAtEnd() }
            }

            Item {
                id: lfoot
                anchors.bottom: parent.bottom
                width: parent.width; height: 18
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.items.length ? root.doneCount + " de " + root.items.length + " comprados" : "Sin elementos"
                    font.pixelSize: 11; font.features: { "tnum": 1 }
                    color: Theme.surfaceText; opacity: 0.4
                }
                StyledText {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    visible: root.doneCount > 0
                    text: root.confirmClear ? "¿Quitar " + root.doneCount + "? Clic para confirmar" : "Quitar los comprados"
                    font.pixelSize: 11; color: root.confirmClear ? "#E0A39A" : Theme.surfaceText; opacity: cdm.containsMouse || root.confirmClear ? 0.9 : 0.45
                    MouseArea { id: cdm; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.confirmClear) root.clearDone(); else { root.confirmClear = true; clearTimeout.restart() } } }
                    // si no confirma en 4 s, vuelve a su texto normal
                    Timer { id: clearTimeout; interval: 4000; onTriggered: root.confirmClear = false }
                }
            }
        }
    }

    // Anillo de avance de una lista
    component Ring: Canvas {
        property real ratio: 0
        property color hue: Theme.surfaceText
        width: 24; height: 24
        onRatioChanged: requestPaint()
        onHueChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"), m = width / 2, r = m - 1.5;
            c.reset();
            c.lineWidth = 2.5; c.lineCap = "round";
            c.strokeStyle = Qt.rgba(hue.r, hue.g, hue.b, 0.18);
            c.beginPath(); c.arc(m, m, r, 0, 2 * Math.PI); c.stroke();
            if (ratio <= 0) return;
            c.strokeStyle = Qt.rgba(hue.r, hue.g, hue.b, 0.9);
            c.beginPath(); c.arc(m, m, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * ratio); c.stroke();
        }
    }
}
