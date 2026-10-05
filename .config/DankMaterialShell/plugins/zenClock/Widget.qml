import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Reloj de la barra: mini reloj de agujas, hora grande con a. m./p. m. pequeño y la fecha tenue.
// El segundero es un punto que recorre el borde del mini reloj. Clic: abre el Resumen a la izquierda, debajo del reloj.
PluginComponent {
    id: root

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    // En una píldora suelta (~/.config/dms-pills) el Resumen se abre debajo de ella; si no, a la izquierda
    pillClickAction: () => {
        const loader = PopoutService.dankDashPopoutLoader;
        let pt = null;
        try { pt = FloatingPillService.popupTrigger(root, Math.max(4, root.barSpacing)); } catch (e) {}
        if (!pt || !loader) {
            Quickshell.execDetached(["dms", "ipc", "call", "dash", "toggleAt", "overview", "left"]);
            return;
        }
        if (loader.item?.dashVisible) {
            loader.item.dashVisible = false;
            return;
        }
        loader.active = true;
        const dash = loader.item;
        if (!dash)
            return;
        dash.setTriggerPosition(pt.x, pt.y, pt.width, "center", root.parentScreen, pt.barPosition, root.barThickness, root.barSpacing, root.barConfig);
        dash.requestTab?.("overview");
        PopoutManager.requestPopout(dash, undefined, "pill-dash-overview");
    }

    // Mini reloj de agujas (segundero = punto en el borde)
    component Face: Canvas {
        width: 17; height: 17
        property date t: root.now
        onTChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"), cx = width / 2, cy = height / 2, r = width / 2 - 1;
            const col = Theme.surfaceText, h = t.getHours() % 12, m = t.getMinutes(), s = t.getSeconds();
            c.reset();
            c.lineCap = "round";
            c.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.35); c.lineWidth = 1.2;
            c.beginPath(); c.arc(cx, cy, r, 0, 2 * Math.PI); c.stroke();
            const hand = (ang, len, w, a) => {
                c.strokeStyle = Qt.rgba(col.r, col.g, col.b, a); c.lineWidth = w;
                c.beginPath(); c.moveTo(cx, cy); c.lineTo(cx + len * Math.cos(ang), cy + len * Math.sin(ang)); c.stroke();
            };
            hand(-Math.PI / 2 + (h + m / 60) * Math.PI / 6, r * 0.5, 1.8, 0.95);
            hand(-Math.PI / 2 + (m + s / 60) * Math.PI / 30, r * 0.78, 1.3, 0.85);
            const sa = -Math.PI / 2 + s * Math.PI / 30;
            c.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.9);
            c.beginPath(); c.arc(cx + r * Math.cos(sa), cy + r * Math.sin(sa), 1.4, 0, 2 * Math.PI); c.fill();
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: 8

            Face { anchors.verticalCenter: parent.verticalCenter }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                StyledText {
                    id: hm
                    text: (root.now.getHours() % 12 || 12) + ":" + String(root.now.getMinutes()).padStart(2, "0")
                    font.pixelSize: Theme.fontSizeMedium; font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Theme.surfaceText
                }
                StyledText {
                    anchors.baseline: hm.baseline
                    text: root.now.getHours() < 12 ? "a. m." : "p. m."
                    font.pixelSize: 9; font.weight: Font.Medium
                    color: Theme.surfaceText; opacity: 0.5
                }
            }

            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 12; color: Theme.surfaceText; opacity: 0.15 }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: { const s = Qt.locale("es_ES").toString(root.now, "ddd d MMM").replace(/\./g, ""); return s.charAt(0).toUpperCase() + s.slice(1) }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText; opacity: 0.6
            }
        }
    }

    // En los bordes laterales: esfera, hora y minutos apilados
    verticalBarPill: Component {
        Column {
            spacing: 3
            Face { anchors.horizontalCenter: parent.horizontalCenter }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.now.getHours() % 12 || 12) + "\n" + String(root.now.getMinutes()).padStart(2, "0")
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 0.9
                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: Theme.surfaceText
            }
        }
    }
}
