import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Una píldora suelta pegada a un borde (barConfig.floatingPills). Carga los widgets con los mismos
// componentes que la barra; arrastrar el hueco entre widgets la mueve, arrastrar un widget lo saca.
// Abajo el espacio lo reserva PillEdgeReserve, arriba la barra y a los lados los gaps de niri. Esta ventana ignora
// las zonas exclusivas: al hacer scroll las ventanas pasan por debajo.
PanelWindow {
    id: win

    required property var pill
    required property var barWindow
    property var barConfig: null
    property var components: null

    readonly property string edge: pill.edge || "bottom"
    // Cada pantalla muestra todas las píldoras: el estado de cada copia va por id@pantalla
    readonly property string key: pill.id + "@" + (screen?.name ?? "")
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property real pad: FloatingPillService.pad
    readonly property real thick: FloatingPillService.thick
    readonly property real margin: FloatingPillService.margin
    readonly property real length: Math.max(thick, (vertical ? col.implicitHeight : row.implicitWidth) + pad * 2)
    // Dónde querría estar (misma cuenta que la vista previa del arrastre). Píldoras antiguas sin align = "start".
    readonly property var geo: FloatingPillService.geometry(edge, pill.align || "start", pill.pos ?? 0, length, screen?.width ?? 0, screen?.height ?? 0)
    // Dónde acaba de verdad: el reparto (FloatingPillService.resolve) la aparta de las demás píldoras
    readonly property real _start: FloatingPillService.resolved[key] ?? (vertical ? geo.y : geo.x)
    // Partida por un obstáculo (volumen en el centro, notificación): desde el widget k va desplazada `extra`
    readonly property var split: FloatingPillService.splits[key] ?? null
    readonly property int splitK: split && split.extra > 0 ? split.k : -1
    readonly property real extra: splitK > 0 ? split.extra : 0
    // Mientras el hueco se cierra sigue partida con el último k
    property int _lastK: -1
    onSplitKChanged: if (splitK > 0) _lastK = splitK
    readonly property int kNow: splitK > 0 ? splitK : (_shownExtra > 0.5 ? _lastK : -1)
    // Sin animación: salta directo al sitio al partirse/juntarse o al apartarse
    property real _shownStart: _start
    property real _shownExtra: extra
    on_StartChanged: _shownStart = _start
    onExtraChanged: _shownExtra = extra
    readonly property real sx: vertical ? geo.x : _shownStart
    readonly property real sy: vertical ? _shownStart : geo.y
    // [inicio, fin] de cada widget a lo largo de la píldora (sin el desplazamiento)
    function _cells() {
        const out = [];
        for (const c of (vertical ? col : row).children)
            if (c.itemData !== undefined && c.visible)
                out.push(vertical ? [col.y + c.y, col.y + c.y + c.height] : [row.x + c.x, row.x + c.x + c.width]);
        return out.sort((a, b) => a[0] - b[0]);
    }
    // Largo de la mitad izquierda y dónde empieza la derecha (sin desplazar)
    readonly property real leftLen: kNow > 0 && _cellsNow.length > kNow ? _cellsNow[kNow - 1][1] + pad : length
    readonly property real rightOff: kNow > 0 && _cellsNow.length > kNow ? _cellsNow[kNow][0] - pad : length
    property var _cellsNow: []

    function _publish() {
        const sw = screen?.width ?? 0, sh = screen?.height ?? 0;
        FloatingPillService.setDesired(key, {
            "screen": screen?.name ?? "",
            "edge": edge,
            "start": vertical ? geo.y : geo.x,
            "len": vertical ? geo.h : geo.w,
            "lo": margin,
            "hi": (vertical ? sh : sw) - margin,
            "sw": sw,
            "sh": sh,
            "cells": _cellsNow
        }, win);
    }
    function _publishRect() {
        // Partida: dos rects (la mitad izquierda con el id, la derecha con id#r), el hueco queda libre
        // Oculta (sin widgets visibles) no ocupa sitio: no reserva borde ni bloquea a otras
        if (!visible) {
            FloatingPillService.setRect(key, null, win);
            FloatingPillService.setRect(key + "#r", null, win);
            return;
        }
        const sp = kNow > 0, a = sp ? leftLen : length;
        FloatingPillService.setRect(key, {
            "screen": screen?.name ?? "",
            "edge": edge,
            "x": sx,
            "y": sy,
            "w": vertical ? geo.w : a,
            "h": vertical ? a : geo.h
        }, win);
        const r = sp ? {
            "screen": screen?.name ?? "",
            "edge": edge,
            "x": vertical ? sx : sx + rightOff + _shownExtra,
            "y": vertical ? sy + rightOff + _shownExtra : sy,
            "w": vertical ? geo.w : length - rightOff,
            "h": vertical ? length - rightOff : geo.h
        } : null;
        FloatingPillService.setRect(key + "#r", r, win);
    }
    on_ShownExtraChanged: _publishRect()
    onKNowChanged: _publishRect()
    function _refreshCells() {
        const c = _cells();
        if (JSON.stringify(c) !== JSON.stringify(_cellsNow)) {
            _cellsNow = c;
            _publish();
        }
    }
    onGeoChanged: {
        _refreshCells();
        _publish();
        _publishRect();
    }
    onSxChanged: _publishRect()
    onVisibleChanged: _publishRect()
    onSyChanged: _publishRect()
    Component.onCompleted: {
        _publish();
        _publishRect();
    }
    Component.onDestruction: FloatingPillService.forget(key, win)

    // Sin ningún widget visible (p. ej. la bandeja sin íconos) no se muestra
    // (por tamaño, no por `visible`: con la ventana oculta todo cuenta como invisible y no volvería a salir)
    visible: {
        for (const c of (vertical ? col : row).children)
            if (c.itemData !== undefined && (vertical ? c.height : c.width) > 0)
                return true;
        return false;
    }
    screen: barWindow.screen
    color: "transparent"
    WlrLayershell.namespace: "dms:pill"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        left: true
    }
    margins {
        top: sy
        left: sx
    }
    implicitWidth: geo.w + (vertical ? 0 : _shownExtra)
    implicitHeight: geo.h + (vertical ? _shownExtra : 0)
    // Solo las dos mitades reciben clics: el hueco del medio es del obstáculo (p. ej. la música de la barra)
    mask: Region {
        item: bgLeft
        Region {
            item: bgRight
        }
    }

    AxisContext {
        id: pillAxis
        edge: win.edge
    }

    Item {
        id: content
        anchors.fill: parent
        // Lo usan DankBarContent y PluginComponent para abrir los paneles junto a la píldora
        readonly property var floatingPillRect: ({
                "x": win.sx,
                "y": win.sy,
                "w": win.implicitWidth,
                "h": win.implicitHeight,
                "edge": win.edge
            })

        // Mitad derecha cuando está partida (sin partir no se ve)
        Rectangle {
            id: bgRight
            visible: win.kNow > 0
            x: win.vertical ? 0 : win.rightOff + win._shownExtra
            y: win.vertical ? win.rightOff + win._shownExtra : 0
            width: win.vertical ? parent.width : (visible ? win.length - win.rightOff : 0)
            height: win.vertical ? (visible ? win.length - win.rightOff : 0) : parent.height
            radius: (win.vertical ? width : height) / 2
            color: Theme.withAlpha(Theme.surfaceContainer, 0.9)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)
        }

        Rectangle {
            id: bgLeft
            width: win.vertical ? parent.width : (win.kNow > 0 ? win.leftLen : parent.width)
            height: win.vertical ? (win.kNow > 0 ? win.leftLen : parent.height) : parent.height
            radius: (win.vertical ? width : height) / 2
            color: Theme.withAlpha(Theme.surfaceContainer, 0.9)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)

            // Arrastrar el hueco entre widgets mueve la píldora entera: a otra píldora (se une) o a otro sitio.
            // Sobre un widget gana el arrastre del widget (PillDragHandle puede quitarle el gesto a este; este no a aquel).
            DragHandler {
                id: moveDrag
                target: null
                grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.ApprovesTakeOverByAnything
                property point last
                onCentroidChanged: {
                    if (!active || !win.screen)
                        return;
                    last = centroid.scenePosition;
                    FloatingPillService.moveDrag(win.sx + last.x, win.sy + last.y, win.screen.width, win.screen.height);
                }
                onActiveChanged: {
                    if (!win.screen)
                        return;
                    if (active) {
                        last = centroid.scenePosition;
                        FloatingPillService.beginDrag(content, win.screen.name, win.barConfig?.id ?? "default", {
                            "kind": "pill",
                            "pillId": win.pill.id,
                            "whole": true
                        });
                        return;
                    }
                    FloatingPillService.endDrag();
                    FloatingPillService.movePill(win.barConfig?.id ?? "default", win.pill.id, win.screen.name, win.sx + last.x, win.sy + last.y, win.screen.width, win.screen.height);
                }
            }
        }

        Component {
            id: cellComp

            Item {
                id: cell
                required property var modelData
                required property int index
                readonly property var itemData: typeof modelData === "string" ? {
                    "widgetId": modelData,
                    "id": modelData + "_" + index,
                    "enabled": true
                } : Object.assign({}, modelData, {
                    "widgetId": modelData.id || modelData.widgetId,
                    "id": (modelData.id || modelData.widgetId) + "_" + index,
                    "enabled": modelData.enabled !== false
                })
                visible: widgetLoader.active && widgetLoader.widgetEnabled
                width: widgetLoader.item ? widgetLoader.item.width : 0
                height: widgetLoader.item ? widgetLoader.item.height : 0
                // La mitad derecha de una píldora partida se corre lo que mide el hueco
                transform: Translate {
                    x: !win.vertical && win.kNow > 0 && row.x + cell.x >= win.rightOff + win.pad - 0.5 ? win._shownExtra : 0
                    y: win.vertical && win.kNow > 0 && col.y + cell.y >= win.rightOff + win.pad - 0.5 ? win._shownExtra : 0
                }

                PillDragHandle {
                    src: ({
                            "kind": "pill",
                            "pillId": win.pill.id,
                            "index": cell.index
                        })
                    barConfig: win.barConfig
                    screen: win.screen
                    vertical: win.vertical
                    origin: Qt.point(win.sx, win.sy)
                }
                WidgetHost {
                    id: widgetLoader
                    anchors.verticalCenter: win.vertical ? undefined : parent.verticalCenter
                    anchors.horizontalCenter: win.vertical ? parent.horizontalCenter : undefined
                    widgetId: cell.itemData.widgetId
                    widgetData: cell.itemData
                    spacerSize: cell.itemData.size || 20
                    components: win.components
                    isInColumn: win.vertical
                    axis: pillAxis
                    section: "right"
                    parentScreen: win.screen
                    widgetThickness: win.barWindow.widgetThickness
                    barThickness: win.barWindow.effectiveBarThickness
                    barSpacing: win.margin
                    barConfig: win.barConfig
                    isFirst: cell.index === 0
                    sectionSpacing: Theme.spacingXS
                }
            }
        }

        Row {
            id: row
            visible: !win.vertical
            x: win.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS
            Repeater {
                model: win.vertical ? [] : win.pill.widgets
                delegate: cellComp
            }
        }

        Column {
            id: col
            visible: win.vertical
            y: win.pad
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingXS
            Repeater {
                model: win.vertical ? win.pill.widgets : []
                delegate: cellComp
            }
        }
    }
}
