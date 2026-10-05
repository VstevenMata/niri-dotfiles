import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Un clic alterna No molestar. Azul = activado.
PluginComponent {
    id: root

    pillClickAction: () => SessionData.setDoNotDisturb(!SessionData.doNotDisturb)

    horizontalBarPill: Component {
        DankIcon {
            name: SessionData.doNotDisturb ? "do_not_disturb_on" : "do_not_disturb_off"
            color: SessionData.doNotDisturb ? Theme.primary : Theme.widgetIconColor
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: SessionData.doNotDisturb ? "do_not_disturb_on" : "do_not_disturb_off"
            color: SessionData.doNotDisturb ? Theme.primary : Theme.widgetIconColor
            size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }
}
