import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

// Superficie invisible que reserva espacio en un borde de una pantalla cuando hay píldoras ahí, como la
// zona de la barra arriba. (layer-shell solo respeta la zona exclusiva si la superficie ocupa el borde entero.)
// Los struts de zen.kdl la compensan (-40 a los lados): con píldoras las apps quedan a `gaps` px del borde y
// la columna vecina fuera de pantalla; sin píldoras, a 6 px.
PanelWindow {
    id: win

    required property string edge
    required property var barWindow
    property var barConfig: null

    // Reserva hasta el final de la píldora + windowGap; niri suma sus gaps y resta sus struts.
    // A los lados 0: la reserva acaba justo al final de la píldora (40) y el strut -40 la compensa
    property int windowGap: edge === "bottom" ? 2 : 0
    property real zone: FloatingPillService.margin + 1 + FloatingPillService.thick + windowGap

    screen: barWindow.screen
    color: "transparent"
    WlrLayershell.namespace: "dms:pill-reserve"
    WlrLayershell.layer: WlrLayer.Bottom
    anchors {
        top: edge !== "bottom"
        bottom: edge !== "top"
        left: edge !== "right"
        right: edge !== "left"
    }
    implicitWidth: 1
    implicitHeight: 1
    exclusiveZone: zone
    mask: Region {}
}
