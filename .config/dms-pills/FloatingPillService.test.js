// Prueba de FloatingPillService (soltar, colocar y repartir) con SettingsData y asas simulados:
//   node ~/.config/dms-pills/FloatingPillService.test.js
const fs = require('fs'), a = require('assert');
let src = fs.readFileSync(__dirname + '/FloatingPillService.qml', 'utf8');
src = src.slice(src.indexOf('function register'), src.lastIndexOf('}'));
let cfg; const SettingsData = { getBarConfig: () => cfg, updateBarConfig: (id, u) => Object.assign(cfg, JSON.parse(JSON.stringify(u))) };
const Qt = { callLater: () => {} };
var handles = [], rects = {}, desired = {}, resolved = {}, dragSize = { width: 40, height: 30 }, thick = 36, margin = 3, pad = 10, pillGap = 3, _resolvePending = false, _dragWhole = false, _dragSolo = "", dragActive = false, dragScreen = "", dragImage = "", obstacles = {}, splits = {};
const root = {};
eval(src); // carga las funciones del propio servicio (archivo local de este directorio) para probarlas fuera de QML
const W = 1920, H = 1200;
const H_ = (src, x, y, w, h, vertical = false) => ({ src, screen: { name: "S" }, visible: true, vertical, globalRect: () => ({ x, y, w, h }) });
// Barra derecha: widgets de 40 px desde x=1500, y=3..41
const barRight = () => cfg.rightWidgets.map((_, i) => H_({ kind: "bar", section: "right", index: i }, 1500 + 40 * i, 3, 40, 38));
const overlap = (r, s) => !(r.x + r.w <= s.x || s.x + s.w <= r.x || r.y + r.h <= s.y || s.y + s.h <= r.y);

// Reordenar dentro de la barra
cfg = { leftWidgets: [], centerWidgets: [], rightWidgets: ["cpu", "notif", "bat"], floatingPills: [] };
handles = barRight();
drop("d", { kind: "bar", section: "right", index: 2 }, "S", 1505, 20, W, H);
a.deepStrictEqual(cfg.rightWidgets, ["bat", "cpu", "notif"]);
handles = barRight();
drop("d", { kind: "bar", section: "right", index: 0 }, "S", 1615, 20, W, H);
a.deepStrictEqual(cfg.rightWidgets, ["cpu", "notif", "bat"]);

// Píldora nueva arriba, donde se soltó (centro)
handles = barRight();
drop("d", { kind: "bar", section: "right", index: 1 }, "S", 700, 15, W, H);
a.deepStrictEqual(cfg.rightWidgets, ["cpu", "bat"]);
const p = cfg.floatingPills[0]; a.equal(p.edge, "top"); a.equal(p.align, "center"); a.equal(p.pos, 700);

// Soltar encima de una píldora: entra en esa posición
handles = barRight().concat([H_({ kind: "pill", pillId: p.id, index: 0 }, 690, 4, 40, 36)]);
drop("d", { kind: "bar", section: "right", index: 0 }, "S", 695, 20, W, H);
a.deepStrictEqual(cfg.floatingPills[0].widgets, ["cpu", "notif"]); a.deepStrictEqual(cfg.rightWidgets, ["bat"]);

// Soltar justo debajo de la barra: pisaría la barra -> bloqueado, no cambia nada
cfg = { leftWidgets: [], centerWidgets: [], rightWidgets: ["cpu", "bat"], floatingPills: [{ id: "q", screen: "S", edge: "left", align: "center", pos: 600, widgets: ["notif", "clock"] }] };
handles = barRight(); rects = {};
const before = JSON.stringify(cfg);
drop("d", { kind: "pill", pillId: "q", index: 0 }, "S", 1530, 60, W, H);
a.equal(JSON.stringify(cfg), before);

// Sacar un widget de una píldora de 2 y soltarlo pegado a ella: bloqueado; más lejos sí, sin mover la otra
cfg = { leftWidgets: [], centerWidgets: [], rightWidgets: [], floatingPills: [{ id: "z", screen: "S", edge: "left", align: "center", pos: 600, widgets: ["clock", "bat"] }] };
handles = [H_({ kind: "pill", pillId: "z", index: 0 }, 4, 560, 36, 40, true), H_({ kind: "pill", pillId: "z", index: 1 }, 4, 600, 36, 40, true)];
rects = { "z@S": { screen: "S", edge: "left", x: 4, y: 550, w: 36, h: 100 } };
drop("d", { kind: "pill", pillId: "z", index: 0 }, "S", 20, 670, W, H);
a.equal(cfg.floatingPills.length, 1);
drop("d", { kind: "pill", pillId: "z", index: 0 }, "S", 20, 760, W, H);
a.equal(cfg.floatingPills.length, 2); a.deepStrictEqual(cfg.floatingPills[0].widgets, ["bat"]); a.equal(cfg.floatingPills[0].pos, 600);
const g2 = geometry("left", cfg.floatingPills[1].align, cfg.floatingPills[1].pos, _newLen("left"), W, H);
a.ok(!overlap(g2, rects["z@S"]), "la nueva no se monta sobre la de origen: " + JSON.stringify(g2));
rects = {};
// ... y en otro borde
cfg.floatingPills = [{ id: "z", screen: "S", edge: "left", align: "center", pos: 600, widgets: ["clock", "bat"] }];
drop("d", { kind: "pill", pillId: "z", index: 1 }, "S", 1900, 600, W, H);
a.equal(cfg.floatingPills.length, 2); a.equal(cfg.floatingPills[1].edge, "right"); a.deepStrictEqual(cfg.floatingPills[1].widgets, ["bat"]);

// Soltarlo encima de su propia píldora: solo reordena
cfg.floatingPills = [{ id: "z", screen: "S", edge: "left", align: "center", pos: 600, widgets: ["clock", "bat"] }];
drop("d", { kind: "pill", pillId: "z", index: 0 }, "S", 20, 635, W, H);
a.deepStrictEqual(cfg.floatingPills[0].widgets, ["bat", "clock"]); a.equal(cfg.floatingPills.length, 1);

// Único widget de una píldora: se mueve la píldora entera
cfg.floatingPills = [{ id: "z", screen: "S", edge: "left", align: "center", pos: 600, widgets: ["clock"] }];
handles = [H_({ kind: "pill", pillId: "z", index: 0 }, 4, 580, 36, 40, true)];
drop("d", { kind: "pill", pillId: "z", index: 0 }, "S", 960, 1190, W, H);
a.equal(cfg.floatingPills.length, 1); a.equal(cfg.floatingPills[0].edge, "bottom"); a.equal(cfg.floatingPills[0].pos, 960);

// Píldora entera sobre la barra: se une al final
cfg = { leftWidgets: [], centerWidgets: [], rightWidgets: ["bat"], floatingPills: [{ id: "m", screen: "S", edge: "left", align: "center", pos: 600, widgets: ["notif"] }] };
handles = barRight();
movePill("d", "m", "S", 1520, 20, W, H);
a.deepStrictEqual(cfg.rightWidgets, ["bat", "notif"]); a.equal(cfg.floatingPills.length, 0);

// Reparto: una píldora que crece empuja a su vecina, sin juntarlas ni salirse
handles = [];
const lim = { screen: "S", edge: "bottom", lo: 3, hi: 1917 };
let r = resolve({ a: Object.assign({ start: 900, len: 200 }, lim), b: Object.assign({ start: 1000, len: 80 }, lim) });
a.equal(r.a, 900); a.equal(r.b, 900 + 200 + pillGap);
r = resolve({ a: Object.assign({ start: 1700, len: 200 }, lim), b: Object.assign({ start: 1800, len: 100 }, lim) });
a.equal(r.b, 1817); a.equal(r.a, 1817 - pillGap - 200);
r = resolve({ a: Object.assign({ start: 100, len: 50 }, lim), b: Object.assign({ start: 400, len: 50 }, lim) });
a.deepStrictEqual(r, { a: 100, b: 400 }); // separadas: no se tocan

// Colocación: imán a la esquina, al centro y anclaje al final (crece hacia dentro)
a.deepStrictEqual(placement("bottom", 30, 60, W, H), { align: "start", pos: 3 });
a.deepStrictEqual(placement("bottom", 975, 60, W, H), { align: "center", pos: 960 });
a.deepStrictEqual(placement("bottom", 1900, 60, W, H), { align: "end", pos: 1917 });
a.equal(geometry("bottom", "center", 960, 100, W, H).x, 910);
a.equal(geometry("bottom", "end", 1917, 100, W, H).x, 1817);
a.equal(geometry("left", "start", 0, 80, W, H).y, 3); // los lados llegan a la esquina
// Al mover una píldora la ventana nueva publica antes de que la vieja (mismo id) se destruya: no debe borrarla
desired = {}; rects = {};
const viejo = {}, nuevo = {};
setDesired("p", { screen: "S", edge: "top", start: 10, len: 50, lo: 3, hi: 1917 }, viejo);
setDesired("p", { screen: "S", edge: "top", start: 99, len: 50, lo: 3, hi: 1917 }, nuevo);
forget("p", viejo);
a.equal(desired.p.start, 99);
forget("p", nuevo);
a.equal(desired.p, undefined);
// Obstáculo en el centro (volumen de la barra): la píldora de varios widgets se parte y lo rodea; sin él, vuelve
const lim2 = { screen: "S", edge: "top", lo: 3, hi: 1917, sw: W, sh: H };
const cells = [[10, 60], [64, 114], [118, 168], [172, 222]]; // 4 widgets, píldora de 232 px centrada en 960
const one = { p: Object.assign({ start: 844, len: 232, cells: cells }, lim2) };
handles = [H_({ kind: "bar", section: "center", index: 0 }, 900, 3, 120, 38)]; // tramo 890..1030 (widget ± 12 de margen, − 2)
let sp = {}; r = resolve(one, sp);
a.equal(sp.p.k, 2);
a.equal(r.p + cells[1][1] + pad, 890 - pillGap); // mitad izquierda acaba antes del volumen
a.equal(r.p + sp.p.extra + cells[2][0] - pad, 1030 + pillGap); // la derecha empieza después
handles = []; sp = {}; r = resolve(one, sp);
a.equal(r.p, 844); a.equal(sp.p, undefined);
// Notificación arriba a la derecha que invade el borde derecho: la píldora lateral se aparta y luego vuelve
const side = { s: { screen: "S", edge: "right", start: 60, len: 52, lo: 44, hi: 1197, sw: W, sh: H } };
obstacles = { n: { screen: "S", x: 1500, y: 48, w: 410, h: 100 } };
r = resolve(side, {}); a.ok(r.s >= 148 + pillGap);
obstacles = {}; r = resolve(side, {}); a.equal(r.s, 60);
// Misma píldora en otra pantalla (clave id@pantalla): al moverla no se estorba a sí misma
rects = { "p1@S": { screen: "S", edge: "bottom", x: 100, y: 1150, w: 60, h: 36 } };
const gb = { x: 100, y: 1160, w: 60, h: 36 };
a.equal(_blocked("S", gb, "p1"), false);
a.equal(_blocked("S", gb, ""), true);
rects = {};
// Esquinas: con una píldora arriba a la izquierda, otra en esa esquina (arriba o al lado) queda bloqueada y la de
// la esquina no se mueve; en la esquina libre de abajo a la izquierda sí entra, pegada al borde
cfg = { leftWidgets: [], centerWidgets: [], rightWidgets: [], floatingPills: [{ id: "c", screen: "S", edge: "top", align: "start", pos: 3, widgets: ["zen"] }, { id: "m", screen: "S", edge: "bottom", align: "center", pos: 960, widgets: ["x"] }] };
handles = []; rects = { "c@S": { screen: "S", edge: "top", x: 3, y: 4, w: 60, h: 36 }, "m@S": { screen: "S", edge: "bottom", x: 930, y: 1160, w: 60, h: 36 } };
const snap = JSON.stringify(cfg.floatingPills);
movePill("d", "m", "S", 10, 15, W, H); a.equal(JSON.stringify(cfg.floatingPills), snap);
movePill("d", "m", "S", 30, 10, W, H); a.equal(JSON.stringify(cfg.floatingPills), snap);
movePill("d", "m", "S", 10, 1190, W, H);
const mm = cfg.floatingPills[1]; a.equal(mm.edge, "bottom"); a.equal(mm.pos, 3); a.equal(cfg.floatingPills[0].pos, 3);
movePill("d", "c", "S", 1910, 600, W, H); movePill("d", "c", "S", 20, 10, W, H); // el dueño sí puede volver a su esquina
a.equal(cfg.floatingPills[0].edge, "top"); a.equal(cfg.floatingPills[0].pos, 3);
// Píldora soltada en la barra (compartida por todas las pantallas): el widget sale de las píldoras de las otras
cfg = { leftWidgets: [], centerWidgets: [], rightWidgets: ["cpu"], floatingPills: [{ id: "a", screen: "S", edge: "left", align: "center", pos: 600, widgets: ["clock"] }, { id: "b", screen: "T", edge: "top", align: "center", pos: 960, widgets: ["clock"] }, { id: "c", screen: "T", edge: "left", align: "center", pos: 600, widgets: ["clock", "bat"] }] };
handles = barRight(); rects = {};
movePill("d", "a", "S", 1505, 20, W, H);
a.deepStrictEqual(cfg.rightWidgets, ["clock", "cpu"]);
a.deepStrictEqual(cfg.floatingPills, [{ id: "c", screen: "T", edge: "left", align: "center", pos: 600, widgets: ["bat"] }]);
// Píldora entera arrastrada junto a otra: su largo es el real (sin sumar otra vez el relleno), cabe a 9 px (gap 5)
cfg = { leftWidgets: [], centerWidgets: [], rightWidgets: [], floatingPills: [{ id: "A", screen: "S", edge: "top", align: "start", pos: 3, widgets: ["notif"] }, { id: "B", screen: "S", edge: "left", align: "center", pos: 600, widgets: ["bat"] }] };
handles = []; rects = { "A@S": { screen: "S", edge: "top", x: 3, y: 4, w: 56, h: 36 } };
dragSize = { width: 56, height: 36 }; _dragWhole = true;
movePill("d", "B", "S", 96, 15, W, H);
a.equal(cfg.floatingPills[1].edge, "top"); a.equal(cfg.floatingPills[1].pos, 68);
_dragWhole = false;
// Oculta (setDesired null) deja de apartar a las demás en el reparto
desired = {}; setDesired("t@S", { screen: "S", edge: "top", start: 1700, len: 60, lo: 3, hi: 1917 }, 1); setDesired("t@S", null, 1);
a.deepStrictEqual(Object.keys(desired), []);
// Arrastrar el único widget de una píldora usa el largo real de la píldora
cfg = { floatingPills: [{ id: "n", screen: "S", edge: "top", align: "end", pos: 1700, widgets: ["notif"] }] };
rects = { "n@S": { screen: "S", edge: "top", x: 1650, y: 4, w: 50, h: 36 } };
Qt.size = (w, h) => ({ width: w, height: h });
beginDrag({ width: 26, height: 30, grabToImage: () => {} }, "S", "d", { kind: "pill", pillId: "n", index: 0 });
a.equal(_newLen("top"), 50); _dragWhole = false; dragActive = false;
// Widget angosto sacado de una píldora de varios: la nueva mide lo que el widget más el relleno, no más
dragSize = { width: 26, height: 30 };
a.equal(_newLen("top"), Math.max(thick, 26 + pad * 2));
dragSize = { width: 40, height: 30 };
console.log("ok");
