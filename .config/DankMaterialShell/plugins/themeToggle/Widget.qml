import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Un clic alterna entre el tema normal y el modo zen (~/.local/bin/theme).
PluginComponent {
    id: root

    pillClickAction: () => Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/theme", "toggle"])

    horizontalBarPill: Component {
        DankIcon {
            name: "spa"
            color: Theme.widgetIconColor
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "spa"
            color: Theme.widgetIconColor
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }
}
