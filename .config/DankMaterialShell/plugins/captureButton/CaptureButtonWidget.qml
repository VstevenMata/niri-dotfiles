import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Un clic abre/cierra la Screen Capture Toolbar (plugin screenCaptureToolbar).
PluginComponent {
    id: root

    pillClickAction: () => Quickshell.execDetached(["dms", "ipc", "call", "screenCaptureToolbar", "toggle"])

    horizontalBarPill: Component {
        DankIcon {
            name: "screenshot_region"
            color: Theme.widgetIconColor
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "screenshot_region"
            color: Theme.widgetIconColor
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }
}
