import QtQuick
import qs.Services

// Asa invisible del tamaño de un widget. Su DragHandler va en el contenedor del widget (parent), no en una
// capa encima: así el clic llega al widget (una capa con manejador encima se lo quedaba). Si arrastras, una
// copia del widget sigue al cursor y al soltar va a la píldora y posición bajo el cursor, o a una píldora
// nueva en ese borde (FloatingPillService.drop).
Item {
    id: root

    property var src: null // { kind: "bar", section, index } | { kind: "pill", pillId, index }
    property var barConfig: null
    property var screen: null
    property bool vertical: false
    // Posición en pantalla del (0,0) de la ventana que contiene el asa
    property point origin: Qt.point(src?.kind === "bar" ? FloatingPillService.barOriginX(screen?.name ?? "", Window.window?.width ?? 0) : 0, 0)
    property point _last: Qt.point(0, 0)

    anchors.fill: parent

    function globalRect() {
        const p = mapToItem(null, 0, 0);
        return {
            "x": p.x + origin.x,
            "y": p.y + origin.y,
            "w": width,
            "h": height
        };
    }

    Component.onCompleted: FloatingPillService.register(root)
    // Un widget de la barra que aparece o cambia de tamaño (volumen, música en el centro): las píldoras se reparten
    onVisibleChanged: if (src?.kind === "bar") FloatingPillService.barChanged()
    onWidthChanged: if (src?.kind === "bar") FloatingPillService.barChanged()
    onXChanged: if (src?.kind === "bar") FloatingPillService.barChanged()
    onOriginChanged: if (src?.kind === "bar") FloatingPillService.barChanged()
    Component.onDestruction: FloatingPillService.unregister(root)

    DragHandler {
        id: drag
        parent: root.parent
        target: null
        // Permisos por defecto: el widget puede quedarse el clic, y este arrastre le quita el gesto al
        // widget al moverse. (CanTakeOverFromAnything quita ApprovesTakeOverByItems y el widget dejaba de recibir clics.)
        onActiveChanged: {
            if (!root.src || !root.screen)
                return;
            if (active) {
                root._last = centroid.scenePosition;
                FloatingPillService.beginDrag(root.parent, root.screen.name, root.barConfig?.id ?? "default", root.src);
                return;
            }
            FloatingPillService.endDrag();
            FloatingPillService.drop(root.barConfig?.id ?? "default", root.src, root.screen.name, root._last.x + root.origin.x, root._last.y + root.origin.y, root.screen.width, root.screen.height);
        }
        onCentroidChanged: {
            if (!active || !root.screen)
                return;
            root._last = centroid.scenePosition;
            FloatingPillService.moveDrag(root._last.x + root.origin.x, root._last.y + root.origin.y, root.screen.width, root.screen.height);
        }
    }

    // El original se atenúa en cuanto la copia ya sigue al cursor
    Binding {
        target: root.parent
        property: "opacity"
        value: 0.3
        when: drag.active && FloatingPillService.dragImage != ""
    }
}
