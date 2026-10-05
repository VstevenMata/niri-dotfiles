import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Clic: enfoca la ventana de Correo UNA si ya está abierta; si no, la abre como app de Chrome.
PluginComponent {
    id: root

    pillClickAction: () => Quickshell.execDetached(["sh", "-c",
        "id=$(niri msg -j windows | jq -r '.[] | select(.app_id == \"chrome-mail.google.com__mail_u_0_-UNA\") | .id' | head -1); " +
        "if [ -n \"$id\" ]; then niri msg action focus-window --id \"$id\"; " +
        "else google-chrome --profile-directory=UNA --disable-extensions --app=https://mail.google.com/mail/u/0/; fi"])

    horizontalBarPill: Component {
        Image {
            source: Qt.resolvedUrl("icon.png")
            width: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
            height: width
            sourceSize: Qt.size(width * 2, height * 2)
            smooth: true
        }
    }

    verticalBarPill: Component {
        Image {
            source: Qt.resolvedUrl("icon.png")
            width: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
            height: width
            sourceSize: Qt.size(width * 2, height * 2)
            smooth: true
        }
    }
}
