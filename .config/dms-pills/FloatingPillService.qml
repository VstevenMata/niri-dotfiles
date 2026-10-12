pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Píldoras sueltas: widgets de la barra arrastrados a cualquier borde de la pantalla.
// Se guardan en barConfig.floatingPills = [{ id, screen, edge: "top"|"bottom"|"left"|"right", align, pos, widgets }],
// pos = coordenada a lo largo del borde (inicio, centro o final según align). Así cada barra (y cada modo
// de ~/.local/bin/theme, que intercambia barConfigs[0]) recuerda las suyas.
// Lo instala ~/.config/dms-pills/patch.py (desde ~/.local/bin/dms-run-custom).
Singleton {
    id: root

    // Asas de arrastre vivas (PillDragHandle): cada una sabe su contenedor, índice y rect en pantalla
    property var handles: []

    // Estado del arrastre en curso, lo dibuja PillDragOverlay
    property bool dragActive: false
    property string dragScreen: ""
    property url dragImage: ""
    property size dragSize: Qt.size(0, 0)
    property point dragPos: Qt.point(0, 0)
    property string _dragSolo: "" // ver _solo()
    property bool _dragWhole: false // se arrastra la píldora entera (dragSize ya incluye su relleno)
    property var hint: null // { x, y, w, h, kind: "insert"|"new"|"blocked", target: {x,y,w,h} }

    // Reparto por borde para que las píldoras no se monten: cada ventana publica dónde querría estar
    // (desired) y dónde está (rects); resolved = inicio final a lo largo del borde
    property var desired: ({})
    property var resolved: ({})
    // Píldoras partidas por un obstáculo: id -> { k: primer widget de la mitad derecha, extra: hueco añadido }
    property var splits: ({})
    // Obstáculos que las píldoras esquivan (notificaciones): id -> { screen, x, y, w, h }
    property var obstacles: ({})
    property var rects: ({})
    property bool _resolvePending: false
    // 5 px a la vista: el borde redondeado (antialias) se come ~1 px de cada píldora, entre rects van 3
    readonly property real pillGap: 3

    // Medidas de la barra (las fija DankBarContent): grosor de píldora y margen al borde
    property real thick: 36
    property real margin: 3
    readonly property real pad: 10

    // Ver barChanged()
    Timer {
        id: barTimer
        interval: 50
        onTriggered: root._resolveLater()
    }

    function register(h) {
        handles = handles.concat([h]);
        _resolveLater();
    }

    function unregister(h) {
        handles = handles.filter(x => x !== h);
        _resolveLater();
    }

    // ---- reparto sin solapes ----

    // owner: la ventana que publica. Al mover una píldora se crea la ventana nueva antes de destruir la vieja
    // (mismo id); forget solo borra si lo publicado sigue siendo de quien olvida.
    // d null: no participa en el reparto (p. ej. oculta, sin widgets visibles)
    function setDesired(id, d, owner) {
        if (!d && !desired[id])
            return;
        const next = Object.assign({}, desired);
        if (d)
            next[id] = Object.assign({ owner: owner }, d);
        else
            delete next[id];
        desired = next;
        _resolveLater();
    }

    function setRect(id, r, owner) {
        if (!r && !rects[id])
            return;
        const next = Object.assign({}, rects);
        if (r)
            next[id] = Object.assign({ owner: owner }, r);
        else
            delete next[id];
        // Una píldora de la izquierda aparece o se va: la barra se corre (barOriginX), repartir de nuevo
        const left = (r || rects[id]).edge === "left" && !r !== !rects[id];
        rects = next;
        if (left)
            barChanged();
    }

    function forget(id, owner) {
        if (owner !== undefined && desired[id]?.owner !== owner)
            return;
        const d = Object.assign({}, desired), r = Object.assign({}, rects);
        delete d[id];
        delete r[id];
        delete r[id + "#r"];
        desired = d;
        rects = r;
        _resolveLater();
    }

    function setObstacle(id, o) {
        if (!o && !obstacles[id])
            return;
        const next = Object.assign({}, obstacles);
        if (o)
            next[id] = o;
        else
            delete next[id];
        obstacles = next;
        _resolveLater();
    }

    // La barra cambió (p. ej. aparece el volumen en el centro): repartir cuando ya se haya recolocado
    function barChanged() {
        _resolveLater(); // ya mismo (sin esto el volumen tapa la píldora unos fotogramas)
        barTimer.restart();
    }

    function _resolveLater() {
        if (_resolvePending)
            return;
        _resolvePending = true;
        Qt.callLater(() => {
            root._resolvePending = false;
            const sp = {};
            root.resolved = root.resolve(root.desired, sp);
            root.splits = sp;
        });
    }

    // Dónde empieza la ventana de la barra en la pantalla. Según el orden de las capas, niri la encoge o no por las
    // reservas de los lados (PillEdgeReserve); si la encoge, empieza tras la reserva de la izquierda.
    // barW: ancho real de la ventana de la barra (sin él se supone que no está encogida).
    function barOriginX(screen, barW) {
        const sw = Quickshell.screens.find(s => s.name === screen)?.width ?? 0;
        if (!barW || barW >= sw)
            return 0;
        for (const id in rects)
            if (rects[id].screen === screen && rects[id].edge === "left")
                return margin + 1 + thick;
        return 0;
    }

    // Tramos ocupados por las píldoras de la barra en el borde de arriba (no se mueven)
    function _barSpans(screen) {
        const g = _groups(screen), out = [];
        for (const k in g)
            if (g[k].container.kind === "bar")
                out.push([g[k].x0 + 2, g[k].x1 - 2]);
        return out;
    }

    // Tramos [a, b] a lo largo del borde que las píldoras no pueden tapar: arriba, los widgets de la barra
    // (el volumen o la música que aparecen en el centro); en cualquier borde, notificaciones que lo invadan.
    function _obstacleSpans(screen, edge, sw, sh) {
        const out = edge === "top" ? _barSpans(screen) : [];
        const band = margin + 1 + thick;
        for (const id in obstacles) {
            const o = obstacles[id];
            if (o.screen !== screen)
                continue;
            const hit = edge === "top" ? o.y < band : edge === "bottom" ? o.y + o.h > sh - band : edge === "left" ? o.x < band : o.x + o.w > sw - band;
            if (hit)
                out.push(edge === "left" || edge === "right" ? [o.y, o.y + o.h] : [o.x, o.x + o.w]);
        }
        out.sort((p, q) => p[0] - q[0]);
        const merged = [];
        for (const sp of out) {
            const last = merged[merged.length - 1];
            if (last && sp[0] <= last[1] + pillGap)
                last[1] = Math.max(last[1], sp[1]);
            else
                merged.push([sp[0], sp[1]]);
        }
        return merged;
    }

    // Cada píldora lo más cerca posible de donde quiere estar, separadas pillGap entre sí y sin tapar obstáculos.
    // Una píldora de varios widgets con un obstáculo en medio se parte en dos mitades que lo rodean (splitsOut);
    // si el obstáculo no le cae en medio, la píldora entera se aparta hacia su lado. Al irse el obstáculo vuelve todo.
    // d: id -> { screen, edge, start, len, lo, hi, sw, sh, cells: [[ini, fin] de cada widget dentro de la píldora] }.
    // Devuelve id -> inicio.
    function resolve(d, splitsOut) {
        const out = {}, groups = {};
        for (const id in d) {
            const k = d[id].screen + "|" + d[id].edge;
            const it = Object.assign({ id: id }, d[id]);
            (groups[k] = groups[k] || []).push(it);
        }
        for (const k in groups) {
            const f = groups[k][0];
            const spans = _obstacleSpans(f.screen, f.edge, f.sw, f.sh);
            const slots = [];
            let prev = -Infinity;
            for (const sp of spans) {
                slots.push([prev, sp[0] - pillGap]);
                prev = sp[1] + pillGap;
            }
            slots.push([prev, Infinity]);
            const bySlot = slots.map(() => []);
            const halves = {};
            for (const it of groups[k]) {
                const cells = it.cells || [];
                const io = cells.length < 2 ? -1 : spans.findIndex(sp => {
                    const c = (sp[0] + sp[1]) / 2;
                    return c > it.start + cells[0][1] && c < it.start + cells[cells.length - 1][0];
                });
                if (io >= 0) { 
                    const c = (spans[io][0] + spans[io][1]) / 2;
                    const n = Math.max(1, Math.min(cells.length - 1, cells.filter(x => it.start + (x[0] + x[1]) / 2 < c).length));
                    const rOff = cells[n][0] - pad;
                    const L = Object.assign({}, it, { len: cells[n - 1][1] + pad });
                    const R = Object.assign({}, it, { id: it.id + "#r", start: it.start + rOff, len: it.len - rOff });
                    halves[it.id] = { L: L, R: R, k: n, rOff: rOff };
                    bySlot[io].push(L);
                    bySlot[io + 1].push(R);
                    continue;
                }
                // Al hueco del lado de su centro; si no cabe ahí, al de al lado
                const c = it.start + it.len / 2;
                const room = j => j >= 0 && j < slots.length && Math.min(slots[j][1], it.hi) - Math.max(slots[j][0], it.lo) >= it.len;
                let j = spans.filter(sp => c > (sp[0] + sp[1]) / 2).length;
                if (!room(j))
                    j = room(j - 1) ? j - 1 : room(j + 1) ? j + 1 : j;
                bySlot[j].push(it);
            }
            for (let j = 0; j < slots.length; j++) {
                const items = bySlot[j].sort((a, b) => a.start - b.start || (a.id < b.id ? -1 : 1));
                let prevEnd = -Infinity;
                for (const it of items) {
                    it.s = Math.max(it.start, prevEnd + pillGap, slots[j][0]);
                    prevEnd = it.s + it.len;
                }
                let limit = Infinity;
                for (let i = items.length - 1; i >= 0; i--) {
                    const it = items[i];
                    limit = Math.min(limit, it.hi, slots[j][1]);
                    if (it.s + it.len > limit)
                        it.s = limit - it.len;
                    it.s = Math.max(it.lo, it.s);
                    limit = it.s - pillGap;
                    if (!halves[it.id.split("#")[0]])
                        out[it.id] = it.s;
                }
            }
            for (const id in halves) {
                const h = halves[id];
                out[id] = h.L.s;
                if (splitsOut)
                    splitsOut[id] = { k: h.k, extra: Math.max(0, h.R.s - (h.L.s + h.rOff)) };
            }
        }
        return out;
    }

    // ¿Pisa g (rect en pantalla) otra píldora (salvo ignore) o un grupo de la barra? Se compara en 2D, así
    // tampoco se montan en las esquinas una de arriba y una del lado.
    function _blocked(screen, g, ignore) {
        const occ = [];
        for (const id in rects) {
            const r = rects[id];
            if (id.split(/[#@]/)[0] !== ignore && r.screen === screen)
                occ.push(r);
        }
        const bg = _groups(screen);
        for (const k in bg)
            if (bg[k].container.kind === "bar")
                occ.push({ x: bg[k].x0 + 2, y: bg[k].y0, w: bg[k].x1 - bg[k].x0 - 4, h: bg[k].y1 - bg[k].y0 });
        return occ.some(o => g.x < o.x + o.w + pillGap && o.x < g.x + g.w + pillGap && g.y < o.y + o.h + pillGap && o.y < g.y + g.h + pillGap);
    }

    // ---- dónde está cada cosa ----

    function _key(section) {
        return section + "Widgets";
    }

    function _ckey(c) {
        return c.kind === "bar" ? "bar:" + c.section : "pill:" + c.pillId;
    }

    // Contenedores visibles (secciones de la barra y píldoras) con sus widgets y su rect en pantalla
    // (x0..x1, y0..y1 = widgets + 12 px de margen)
    function _groups(screen) {
        const groups = {};
        for (const h of handles) {
            if (!h.src || !h.screen || h.screen.name !== screen || !h.visible)
                continue;
            const c = h.src;
            const r = h.globalRect();
            if (r.w <= 0 || r.h <= 0)
                continue;
            const k = _ckey(c);
            (groups[k] = groups[k] || { key: k, container: c, vertical: h.vertical, items: [] }).items.push({ index: c.index, r: r });
        }
        for (const k in groups) {
            const g = groups[k];
            g.x0 = Math.min(...g.items.map(i => i.r.x)) - 12;
            g.y0 = Math.min(...g.items.map(i => i.r.y)) - 12;
            g.x1 = Math.max(...g.items.map(i => i.r.x + i.r.w)) + 12;
            g.y1 = Math.max(...g.items.map(i => i.r.y + i.r.h)) + 12;
        }
        return groups;
    }

    // Contenedor bajo el punto y el índice donde insertar. exclude: claves ("bar:right", "pill:<id>")
    // que no cuentan. Devuelve { container, index, hint } o null.
    function containerAt(screen, gx, gy, exclude) {
        const groups = _groups(screen);
        for (const k in groups) {
            const g = groups[k];
            if ((exclude || []).includes(k))
                continue;
            if (gx < g.x0 || gx > g.x1 || gy < g.y0 || gy > g.y1)
                continue;
            g.items.sort((a, b) => a.index - b.index);
            const v = g.vertical;
            const at = g.items.find(i => (v ? gy < i.r.y + i.r.h / 2 : gx < i.r.x + i.r.w / 2));
            const last = g.items[g.items.length - 1];
            const index = at ? at.index : last.index + 1;
            // Barra de inserción en el hueco donde caerá, y el contorno de la píldora destino
            const ref = at ? at.r : last.r;
            const lx = v ? ref.x + 4 : (at ? ref.x - 2 : ref.x + ref.w) - 1.5;
            const ly = v ? (at ? ref.y - 2 : ref.y + ref.h) - 1.5 : ref.y + 6;
            const pillRect = v ? { x: g.x0 + 11, y: g.y0 + 2, w: g.x1 - g.x0 - 22, h: g.y1 - g.y0 - 4 } : { x: g.x0 + 2, y: g.y0 + 11, w: g.x1 - g.x0 - 4, h: g.y1 - g.y0 - 22 };
            return {
                container: { kind: g.container.kind, section: g.container.section, pillId: g.container.pillId },
                index: index,
                hint: { x: lx, y: ly, w: v ? ref.w - 8 : 3, h: v ? 3 : ref.h - 12, kind: "insert", target: pillRect }
            };
        }
        return null;
    }

    // Borde más cercano al punto
    function nearestEdge(gx, gy, sw, sh) {
        const d = {
            "top": gy,
            "bottom": sh - gy,
            "left": gx,
            "right": sw - gx
        };
        return Object.keys(d).reduce((a, b) => d[b] < d[a] ? b : a);
    }

    // Rect en pantalla de una píldora: edge, align ("start"|"center"|"end"), pos a lo largo del borde
    // (inicio, centro o final de la píldora según align) y su largo. Lo usan la ventana y la vista previa.
    function geometry(edge, align, pos, len, sw, sh) {
        const vert = edge === "left" || edge === "right";
        const S = vert ? sh : sw, lo = margin, hi = S - margin;
        let start = align === "center" ? pos - len / 2 : (align === "end" ? pos - len : pos);
        start = Math.round(Math.max(lo, Math.min(hi - len, start)));
        const m = margin + 1;
        const cross = edge === "top" ? m : (edge === "bottom" ? sh - m - thick : (edge === "left" ? m : sw - m - thick));
        return vert ? { x: cross, y: start, w: thick, h: len } : { x: start, y: cross, w: len, h: thick };
    }

    // Dónde queda una píldora soltada con el cursor en p (a lo largo del borde): centrada en el cursor;
    // en el tercio central se ancla al centro (imán al centro exacto), si no al inicio/final (imán a la esquina).
    // Así crece hacia dentro: si el volumen se ensancha, la del centro sigue centrada.
    function placement(edge, p, len, sw, sh) {
        const vert = edge === "left" || edge === "right";
        const S = vert ? sh : sw, lo = margin, snap = 40;
        if (Math.abs(p - S / 2) < S / 6)
            return { align: "center", pos: Math.abs(p - S / 2) < snap ? S / 2 : p };
        if (p < S / 2) {
            const pos = p - len / 2;
            return { align: "start", pos: pos < lo + snap ? lo : pos };
        }
        const pos = p + len / 2;
        return { align: "end", pos: pos > S - margin - snap ? S - margin : pos };
    }

    // Largo aproximado de la píldora nueva con lo que se arrastra
    function _newLen(edge) {
        const vert = edge === "left" || edge === "right";
        const w = dragSize.width || 40, h = dragSize.height || 36;
        if (_dragWhole)
            return Math.max(thick, w, h);
        return vert ? Math.max(thick, (w > h ? thick : h) + pad * 2) : Math.max(thick, w + pad * 2);
    }

    // Id de la píldora que se mueve entera (arrastre de la píldora, o de su único widget): no puede ser su propio destino
    function _solo(barId, src) {
        if (src.kind !== "pill")
            return "";
        const p = (SettingsData.getBarConfig(barId)?.floatingPills || []).find(p => p.id === src.pillId);
        return src.whole || (p && p.widgets.length === 1) ? src.pillId : "";
    }

    // Qué pasa si se suelta aquí: { hit } (entra en la píldora bajo el cursor) o { edge, pl, g } (píldora nueva).
    // La usan la vista previa y el soltar, así lo que se ve es lo que pasa.
    // - solo: id de la píldora que se mueve entera (nunca es su propio destino ni estorba)
    // La píldora nueva va justo donde se soltó; si ahí pisa otra queda bloqueada (blocked): no se suelta
    // y la que ya estaba no se mueve.
    function target(screen, gx, gy, sw, sh, solo) {
        const hit = containerAt(screen, gx, gy, solo ? ["pill:" + solo] : []);
        if (hit)
            return { hit: hit };
        const edge = nearestEdge(gx, gy, sw, sh), len = _newLen(edge);
        const vert = edge === "left" || edge === "right";
        const pl = placement(edge, vert ? gy : gx, len, sw, sh);
        const g = geometry(edge, pl.align, pl.pos, len, sw, sh);
        return { edge: edge, pl: pl, g: g, blocked: _blocked(screen, g, solo) };
    }

    // ---- arrastre (lo llaman las asas) ----

    function beginDrag(item, screen, barId, src) {
        dragScreen = screen;
        dragSize = Qt.size(item.width, item.height);
        dragImage = "";
        _dragSolo = _solo(barId, src);
        // Píldora de un solo widget: se mueve entera, con su largo real (no el del widget más un relleno aproximado)
        const pr = _dragSolo ? rects[_dragSolo + "@" + screen] : null;
        if (pr)
            dragSize = Qt.size(pr.w, pr.h);
        _dragWhole = !!src.whole || !!pr;
        item.grabToImage(r => root.dragImage = r.url);
        dragActive = true;
    }

    function moveDrag(gx, gy, sw, sh) {
        dragPos = Qt.point(gx, gy);
        const t = target(dragScreen, gx, gy, sw, sh, _dragSolo);
        hint = t.hit ? t.hit.hint : { x: t.g.x, y: t.g.y, w: t.g.w, h: t.g.h, kind: t.blocked ? "blocked" : "new" };
    }

    function endDrag() {
        dragActive = false;
        hint = null;
        dragImage = "";
    }

    function _newId() {
        return "p" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    function _setPlace(p, t) {
        p.edge = t.edge;
        p.align = t.pl.align;
        p.pos = Math.round(t.pl.pos);
        delete p.x;
        delete p.y;
    }

    // ---- cambios en la config ----

    // La barra es la misma en todas las pantallas y las píldoras son de cada una: un widget que entra a la barra
    // se quita de las píldoras de las otras pantallas (si no, sale dos veces allí).
    function _intoBar(pills, screen, widgets) {
        const ids = widgets.map(w => w?.id ?? w);
        for (const p of pills)
            if (p.screen !== screen)
                p.widgets = p.widgets.filter(w => !ids.includes(w?.id ?? w));
    }

    // src: { kind: "bar", section, index } | { kind: "pill", pillId, index }
    // Sobre una píldora (de la barra o suelta) -> se inserta ahí en esa posición;
    // si no -> píldora nueva en el borde más cercano, donde se soltó (si ahí hay otra, no hace nada).
    function drop(barId, src, screen, gx, gy, sw, sh) {
        const cfg = SettingsData.getBarConfig(barId);
        if (!cfg)
            return;
        const pills = JSON.parse(JSON.stringify(cfg.floatingPills || []));
        const updates = {};
        const list = c => {
            if (c.kind === "pill")
                return pills.find(p => p.id === c.pillId)?.widgets ?? null;
            const k = _key(c.section);
            return updates[k] || (updates[k] = JSON.parse(JSON.stringify(cfg[k] || [])));
        };

        const solo = _solo(barId, src);
        const t = target(screen, gx, gy, sw, sh, solo);
        const from = list(src);
        if (t.blocked || !from || src.index >= from.length)
            return;

        if (t.hit) {
            const to = list(t.hit.container);
            if (!to)
                return;
            let at = t.hit.index;
            if (from === to && src.index < at)
                at--;
            if (from === to && at === src.index)
                return;
            const entry = from.splice(src.index, 1)[0];
            to.splice(Math.min(at, to.length), 0, entry);
            if (t.hit.container.kind === "bar" && src.kind === "pill")
                _intoBar(pills, screen, [entry]);
        } else if (solo) {
            // Único widget de la píldora: se mueve la píldora entera
            _setPlace(pills.find(p => p.id === solo), t);
        } else {
            const p = { id: _newId(), screen: screen, widgets: [from.splice(src.index, 1)[0]] };
            _setPlace(p, t);
            pills.push(p);
        }

        updates.floatingPills = pills.filter(p => p.widgets.length > 0);
        SettingsData.updateBarConfig(barId, updates);
    }

    // Arrastrar la píldora entera: sobre otra píldora se une a ella; si no, va donde se soltó (si está libre)
    function movePill(barId, pillId, screen, gx, gy, sw, sh) {
        const cfg = SettingsData.getBarConfig(barId);
        const pills = JSON.parse(JSON.stringify(cfg?.floatingPills || []));
        const p = pills.find(p => p.id === pillId);
        if (!p)
            return;
        const t = target(screen, gx, gy, sw, sh, pillId);
        if (t.blocked)
            return;
        if (!t.hit) {
            _setPlace(p, t);
            SettingsData.updateBarConfig(barId, {
                floatingPills: pills
            });
            return;
        }
        const updates = {};
        let to;
        if (t.hit.container.kind === "pill") {
            to = pills.find(q => q.id === t.hit.container.pillId).widgets;
        } else {
            const k = _key(t.hit.container.section);
            to = updates[k] = JSON.parse(JSON.stringify(cfg[k] || []));
        }
        to.splice(Math.min(t.hit.index, to.length), 0, ...p.widgets);
        if (t.hit.container.kind === "bar")
            _intoBar(pills, screen, p.widgets);
        updates.floatingPills = pills.filter(q => q.id !== pillId && q.widgets.length > 0);
        SettingsData.updateBarConfig(barId, updates);
    }

    // ---- paneles ----

    // Rect en pantalla de la píldora suelta que contiene item, o null
    function pillRectOf(item) {
        for (let o = item; o; o = o.parent)
            if (o.floatingPillRect !== undefined)
                return o.floatingPillRect;
        return null;
    }

    // Si item vive en una píldora suelta, dónde abrir su panel: hacia dentro de la pantalla desde
    // la píldora. Devuelve { x, y, width, barPosition } (Position: 0 arriba, 1 abajo, 2 izq., 3 der.) o null.
    function popupTrigger(item, gap) {
        const r = pillRectOf(item);
        if (!r)
            return null;
        const p = item.mapToItem(null, 0, 0);
        const gx = r.x + p.x, gy = r.y + p.y;
        switch (r.edge) {
        case "left":
            return { x: r.x + r.w + gap, y: gy + item.height / 2, width: item.height, barPosition: 2 };
        case "right":
            return { x: r.x - gap, y: gy + item.height / 2, width: item.height, barPosition: 3 };
        case "top":
            return { x: gx, y: r.y + r.h + gap, width: item.width, barPosition: 0 };
        default:
            return { x: gx, y: r.y - gap, width: item.width, barPosition: 1 };
        }
    }
}
