#!/usr/bin/env python3
# Píldoras sueltas para DMS: arrastrar widgets de la barra a cualquier borde, ordenarlos y moverlos
# entre píldoras. Lo llama ~/.local/bin/dms-run-custom (patch_pills) sobre la copia recién hecha de DMS.
# Todo o nada: si algún trozo no encaja (DMS cambió ese código) no escribe nada y sale con error,
# y DMS arranca sin píldoras.
#   uso: patch.py <copia de DMS>
import os
import shutil
import sys

DST = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
BAR = os.path.join(DST, "Modules/DankBar")
files = {}


def edit(rel, old, new, count=1):
    p = os.path.join(DST, rel)
    s = files.get(p) or open(p).read()
    assert s.count(old) == count, f"{rel}: no encaja {old[:60]!r}"
    files[p] = s.replace(old, new)


def handle(section, ind, extra=""):
    p = " " * ind
    return (f"{p}PillDragHandle {{\n{extra}"
            f"{p}    src: ({{ kind: \"bar\", section: \"{section}\", index: index }})\n"
            f"{p}    barConfig: root.barConfig\n"
            f"{p}    screen: root.parentScreen\n"
            f"{p}}}\n")


# Asa de arrastre encima de cada widget de la barra (solo barras horizontales)
for f, sec in [("LeftSection.qml", "left"), ("RightSection.qml", "right")]:
    p = os.path.join(BAR, f)
    s = open(p).read()
    i = s.index("id: rowComp")
    j = s.index("WidgetHost {", i)
    ls = s.rfind("\n", 0, j) + 1
    files[p] = s[:ls] + handle(sec, j - ls) + s[ls:]
edit("Modules/DankBar/CenterSection.qml", "            WidgetHost {\n                id: widgetLoader",
     handle("center", 12, " " * 16 + "visible: !root.isVertical\n"
            # El centro coloca el widget de dentro (item.x), no este contenedor: el asa lo sigue
            + " " * 16 + "anchors.fill: undefined\n"
            + " " * 16 + "x: widgetLoader.item ? widgetLoader.item.x : 0\n"
            + " " * 16 + "width: widgetLoader.item ? widgetLoader.item.width : 0\n"
            + " " * 16 + "height: parent.height\n") + "            WidgetHost {\n                id: widgetLoader")

# DankBarContent: coordenadas y paneles de widgets en píldoras, y las ventanas de las píldoras
C = "Modules/DankBar/DankBarContent.qml"
edit(C, "import QtQuick\n", "import QtQuick\nimport Quickshell\n")
edit(C, "            return Qt.point(raw.x + (barWindow?.hostOriginX ?? 0), raw.y + (barWindow?.hostOriginY ?? 0));",
     """            const pill = FloatingPillService.pillRectOf(item);
            if (pill)
                return Qt.point(raw.x + pill.x, raw.y + pill.y);
            return Qt.point(raw.x + (barWindow?.hostOriginX ?? 0), raw.y + (barWindow?.hostOriginY ?? 0));""")
edit(C, """            if (geom.triggerPos) {
                const pos =""", """            // Widget en una píldora suelta: el panel se abre hacia dentro de la pantalla desde ella
            const pt = FloatingPillService.popupTrigger(spec.visualItem || spec.widgetItem.visualContent || spec.widgetItem, Math.max(4, effectiveBarConfig?.spacing ?? 4));
            if (pt) {
                popout.setTriggerPosition(pt.x, pt.y, pt.width, widgetSection, barWindow.screen, pt.barPosition, barWindow.effectiveBarThickness, effectiveBarConfig?.spacing ?? 4, effectiveBarConfig);
            } else if (geom.triggerPos) {
                const pos =""")
p = os.path.join(DST, C)
s = files[p]
i = s.rstrip().rfind("}")
files[p] = s[:i].rstrip() + """

    // ---- Píldoras sueltas (~/.config/dms-pills) ----

    // Medidas que comparten las píldoras sueltas y la vista previa del arrastre
    readonly property bool _ownsPills: !(barConfig?.island ?? false) && barConfig?.id === "default"
    Binding {
        target: FloatingPillService
        property: "thick"
        value: topBarContent.barWindow.effectiveBarThickness - 2
        when: topBarContent._ownsPills
    }
    Binding {
        target: FloatingPillService
        property: "margin"
        value: topBarContent.barConfig?.spacing ?? 4
        when: topBarContent._ownsPills
    }

    // Píldoras de esta barra en esta pantalla (cada pantalla las suyas), y el espacio que reservan
    readonly property var _floatingPills: (barConfig?.island ?? false) ? [] : (barConfig?.floatingPills ?? []).filter(p => p.screen === (barWindow?.screen?.name ?? "") && p.edge)

    Variants {
        // Bordes de esta pantalla con píldoras visibles (arriba ya reserva la barra). Cada pantalla por su cuenta.
        model: ["bottom", "left", "right"].filter(e => Object.values(FloatingPillService.rects).some(r => r.edge === e && r.screen === (topBarContent.barWindow?.screen?.name ?? "")))
        delegate: PillEdgeReserve {
            required property var modelData
            edge: modelData
            barWindow: topBarContent.barWindow
            barConfig: topBarContent.barConfig
        }
    }

    Variants {
        model: topBarContent._floatingPills
        delegate: FloatingPillWindow {
            required property var modelData
            pill: modelData
            barWindow: topBarContent.barWindow
            barConfig: topBarContent.barConfig
            components: topBarContent.allComponents
        }
    }

    // Vista previa del arrastre de widgets/píldoras en esta pantalla
    Loader {
        active: FloatingPillService.dragActive && FloatingPillService.dragScreen === (topBarContent.barWindow?.screen?.name ?? "") && !(topBarContent.barConfig?.island ?? false)
        sourceComponent: PillDragOverlay {
            screen: topBarContent.barWindow.screen
        }
    }
}
"""

# Las píldoras sueltas de arriba quedan fuera de la zona de clics de la barra (si no, la barra se queda sus clics)
edit("Modules/DankBar/DankBarWindow.qml", """            height: active ? body.inputMaskItem.height : 0
        }
    }
""", """            height: active ? body.inputMaskItem.height : 0
        }

        // Huecos de las píldoras sueltas de arriba
        Region {
            intersection: Intersection.Subtract
            regions: barWindow._pillHoles
        }
    }

    readonly property var _topPillRects: Object.keys(FloatingPillService.rects).map(k => FloatingPillService.rects[k]).filter(r => r.edge === "top" && r.screen === modelData?.name)
    property var _pillHoles: []
    Component {
        id: pillHoleComp
        Region {}
    }
    // Diferido: al conectar un monitor Quickshell recorre los hijos de esta ventana (reloadRecursive);
    // crear Regions hijas en ese momento invalida su lista y crashea (SIGSEGV en QMetaObject::cast)
    on_TopPillRectsChanged: Qt.callLater(_rebuildPillHoles)
    function _rebuildPillHoles() {
        const old = _pillHoles;
        // Rects en pantalla -> coordenadas de la barra (corrida si hay píldoras a la izquierda)
        const ox = FloatingPillService.barOriginX(modelData?.name ?? "", barWindow.width);
        _pillHoles = _topPillRects.map(r => pillHoleComp.createObject(barWindow, {
                "x": r.x - ox,
                "y": r.y,
                "width": r.w,
                "height": r.h
            }));
        old.forEach(h => h.destroy());
    }
""")

# Barra vacía (ningún widget visible ni píldoras arriba): no reserva su zona y las apps suben, como abajo.
# Al aparecer algo (p. ej. zenWaves con música) vuelve a reservar.
edit("Modules/DankBar/DankBarBody.qml", "    readonly property real surfaceExclusiveZone: ",
     "    readonly property bool _pillsBarEmpty: !barWindow.isVertical && [_leftSection, _centerSection, _rightSection].every(s => (s?.implicitWidth ?? 0) <= 4) && !(hostWindow._topPillRects?.length)\n"
     "    readonly property real surfaceExclusiveZone: _pillsBarEmpty ? 0 : ")

# Plugins: sin versión vertical usan la horizontal en los bordes laterales; paneles junto a su píldora
P = "Modules/Plugins/PluginComponent.qml"
edit(P, "import qs.Common\n", "import qs.Common\nimport qs.Services\n")
edit(P, """    width: isVertical ? (hasVerticalPill ? verticalPill.width : 0) : (hasHorizontalPill ? horizontalPill.width : 0)
    height: isVertical ? (hasVerticalPill ? verticalPill.height : 0) : (hasHorizontalPill ? horizontalPill.height : 0)""",
     """    // Sin versión vertical, en un borde lateral se usa la horizontal (mejor que quedar invisible)
    readonly property bool _hasAnyPill: hasVerticalPill || hasHorizontalPill
    width: isVertical ? (_hasAnyPill ? verticalPill.width : 0) : (hasHorizontalPill ? horizontalPill.width : 0)
    height: isVertical ? (_hasAnyPill ? verticalPill.height : 0) : (hasHorizontalPill ? horizontalPill.height : 0)""")
edit(P, "        visible: isVertical && hasVerticalPill\n", "        visible: isVertical && _hasAnyPill\n")
edit(P, "        content: root.verticalBarPill\n", "        content: root.verticalBarPill ?? root.horizontalBarPill\n")
edit(P, "        pluginPopout.setTriggerPosition(pos.x, pos.y, pos.width, section, currentScreen, barPosition, barThickness, barSpacing, barConfig);",
     """        const pt = FloatingPillService.popupTrigger(pill.visualContent, Math.max(4, barSpacing));
        if (pt)
            pluginPopout.setTriggerPosition(pt.x, pt.y, pt.width, section, currentScreen, pt.barPosition, barThickness, barSpacing, barConfig);
        else
            pluginPopout.setTriggerPosition(pos.x, pos.y, pos.width, section, currentScreen, barPosition, barThickness, barSpacing, barConfig);""", count=2)

# Los widgets abren su panel al hacer clic (soltar), no al presionar: así arrastrar un widget no lo abre
# (el DragHandler de PillDragHandle le quita el gesto al MouseArea y el clic no llega).
edit("Modules/Plugins/BasePill.qml", """            rippleLayer.trigger(ripplePos.x, ripplePos.y);
            if (popoutTarget) {""", """            rippleLayer.trigger(ripplePos.x, ripplePos.y);
        }
        onClicked: function (mouse) {
            if (mouse.button !== Qt.LeftButton)
                return;
            if (popoutTarget) {""")
# Al clic, el panel del widget se abre junto a su píldora suelta (no donde estaría en la barra)
edit("Modules/Plugins/BasePill.qml", """                    popoutTarget.setTriggerPosition(pos.x, pos.y, pos.width, section, currentScreen, barPosition, barThickness, root.barSpacing, root.barConfig);""",
     """                    const pt = FloatingPillService.popupTrigger(root.visualContent, Math.max(4, root.barSpacing));
                    if (pt)
                        popoutTarget.setTriggerPosition(pt.x, pt.y, pt.width, section, currentScreen, pt.barPosition, barThickness, root.barSpacing, root.barConfig);
                    else
                        popoutTarget.setTriggerPosition(pos.x, pos.y, pos.width, section, currentScreen, barPosition, barThickness, root.barSpacing, root.barConfig);""")
for w in ["Battery", "RamMonitor", "CpuMonitor", "CpuTemperature", "GpuTemperature", "ClipboardButton", "ColorPicker", "Vpn", "SystemUpdate"]:
    edit(f"Modules/DankBar/Widgets/{w}.qml", "        onPressed: ", "        onClicked: ")

# Notificaciones: mientras se ven, las píldoras que tapen se apartan (FloatingPillService.setObstacle)
N = "Modules/Notifications/Popup/NotificationPopup.qml"
edit(N, """    Component.onDestruction: {
        closeTransientUi();""", """    readonly property string _pillObstacleId: "notif:" + String(win)
    readonly property var _pillObstacle: screen && visible && !exiting ? {
        "screen": screen.name,
        "x": getContentX(),
        "y": getAllocatedContentY(),
        "w": alignedWidth,
        "h": allocatedAlignedHeight
    } : null
    on_PillObstacleChanged: FloatingPillService.setObstacle(_pillObstacleId, _pillObstacle)

    Component.onDestruction: {
        FloatingPillService.setObstacle(_pillObstacleId, null);
        closeTransientUi();""")

# Todo encajó: escribir y copiar los archivos nuevos
for p, s in files.items():
    open(p, "w").write(s)
shutil.copy(os.path.join(HERE, "FloatingPillService.qml"), os.path.join(DST, "Services"))
for f in ["PillDragHandle.qml", "FloatingPillWindow.qml", "PillEdgeReserve.qml", "PillDragOverlay.qml"]:
    shutil.copy(os.path.join(HERE, f), BAR)
print("dms-pills: aplicado")
