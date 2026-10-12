# Lanzador de apps (Super+Espacio, estilo "full" = DankLauncherV2ModalStandalone):
#  - hoja a todo el ancho que baja desde el borde de arriba tapando la barra (capa overlay),
#    con fade; al cerrar vuelve a subir. Apps en cuadrícula de 16 columnas a todo el ancho; la hoja mide 3 filas de apps.
#    Duraciones propias: no depende de animationSpeed, que está en 0 para todo lo demás.
#  - interfaz limpia: filas solo con el nombre (la descripción aparece en la seleccionada),
#    la seleccionada con fondo tenue y una rayita bermellón (el rojo de la pantalla de bloqueo),
#    sin el ícono azul de flatpak, búsqueda sin borde, pie sin franja de color y sin fila de atajos.
# Todo o nada: si algo no encaja, no se escribe ningún archivo.
import os, sys

d = os.path.join(sys.argv[1], "Modals/DankLauncherV2")
files = {}

def sub(f, old, new, n=1):
    if f not in files:
        files[f] = open(os.path.join(d, f)).read()
    assert files[f].count(old) == n, (f, old[:60])
    files[f] = files[f].replace(old, new)

ACCENT = "#c8302b"
RADIUS = 20  # esquinas de abajo

M = "DankLauncherV2ModalStandalone.qml"
DROP = "alignedHeight * 0.4"  # cuánto recorre al bajar
sub(M, "    readonly property int modalWidth: Math.min(baseWidth, screenWidth - 100)\n",
    "    readonly property int modalWidth: screenWidth\n")
sub(M, "    readonly property int modalHeight: Math.min(baseHeight, screenHeight - 100)\n",
    "    readonly property int modalHeight: 470  // búsqueda + encabezado + 3 filas de apps + pie\n")
sub(M, "    readonly property real modalX: (screenWidth - modalWidth) / 2\n", "    readonly property real modalX: 0\n")
sub(M, "    readonly property real modalY: (screenHeight - modalHeight) / 2\n", "    readonly property real modalY: 0\n")
# encima de la barra
sub(M, "    readonly property bool usesOverlayLayer: useBackgroundDarken || SettingsData.launcherUseOverlayLayer || triggerUsesOverlayLayer\n",
    "    readonly property bool usesOverlayLayer: true\n")
sub(M, """                    id: launcherContentLoader
                    anchors.fill: parent
""", """                    id: launcherContentLoader
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 48
""")
sub(M, "    readonly property real windowY: Math.max(0, Theme.snap(alignedY - shadowPad, dpr))",
    f"""    // la ventana empieza en el borde de la pantalla: lo que sube queda fuera y parece bajar desde ahí
    readonly property real windowY: Theme.snap(alignedY, dpr)
    // al abrir, la ventana tarda en mapearse y luego se traba un poco cargando la lista:
    // la entrada arranca después (mientras, se dibuja al 1 %), si no se la come el tirón
    property bool _armed: false
    readonly property bool _shown: contentVisible && _armed
    Timer {{
        interval: 60
        running: root.contentVisible && launcherWindow.backingWindowVisible && !root._armed
        onTriggered: root._armed = true
    }}
    property real _drop: _shown ? 0 : -{DROP}
    Behavior on _drop {{
        NumberAnimation {{
            duration: 400
            easing.type: Easing.OutCubic
        }}
    }}""")
sub(M, "interval: Math.max(Theme.modalAnimationDuration + 50,", "interval: Math.max(440,")
sub(M, "duration: Theme.modalAnimationDuration\n", "duration: 400\n", 3)
sub(M, "            blurY: modalContainer.y + ", "            blurY: modalContainer.y + root._drop + ")
sub(M, "        id: launcherWindow\n",
    "        id: launcherWindow\n        onBackingWindowVisibleChanged: if (!backingWindowVisible) root._armed = false\n")
sub(M, "            opacity: contentVisible ? 1 : 0\n", "            opacity: root._shown ? 1 : 0.01\n")
sub(M, "            transformOrigin: Item.Center\n",
    "            transformOrigin: Item.Center\n            transform: Translate { y: root._drop }\n")
sub(M, "                targetRadius: root.cornerRadius\n",
    f"                targetRadius: {RADIUS}\n                topLeftRadius: 0\n                topRightRadius: 0\n")
sub(M, """                radius: root.cornerRadius
                color: "transparent"
                border.color: BlurService.borderColor""", f"""                radius: {RADIUS}
                topLeftRadius: 0
                topRightRadius: 0
                color: "transparent"
                border.color: BlurService.borderColor""")

R = "ResultItem.qml"
sub(R, """    color: isSelected ? Theme.primaryPressed : isHovered ? Theme.primaryHoverLight : Theme.withAlpha(Theme.primaryHoverLight, 0)
    radius: Theme.cornerRadius
""", """    color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, isSelected ? 0.07 : isHovered ? 0.035 : 0)
    radius: 12
""")
sub(R, """    AppIconRenderer {
        id: iconRenderer""", f"""    Rectangle {{
        visible: root.isSelected
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 18
        radius: 1.5
        color: "{ACCENT}"
    }}

    AppIconRenderer {{
        id: iconRenderer""")
sub(R, """            color: Theme.surfaceText
            wrapMode: Text.WordWrap
            maximumLineCount: 1""", """            color: Theme.surfaceText
            opacity: root.isSelected ? 1 : 0.85
            wrapMode: Text.WordWrap
            maximumLineCount: 1""")
sub(R, """            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap""", """            color: Theme.surfaceVariantText
            opacity: 0.75
            wrapMode: Text.WordWrap""")
# descripción de las apps solo en la seleccionada (archivos/ajustes la siguen mostrando: es su ruta)
sub(R, """            visible: (root.item?.subtitle ?? "").length > 0""",
    """            visible: (root.isSelected || root.item?.type !== "app") && (root.item?.subtitle ?? "").length > 0""")
sub(R, """            source: root.item?.type === "app" ? (root.item.source || "") : \"\"""", """            source: \"\"""")

G = "GridItem.qml"
sub(G, """    radius: Theme.cornerRadius
    color: isSelected ? Theme.primaryPressed : isHovered ? Theme.primaryHoverLight : Theme.withAlpha(Theme.primaryHoverLight, 0)
""", """    radius: 16
    color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, isSelected ? 0.07 : isHovered ? 0.035 : 0)
""")
sub(G, """    SourceBadge {
        anchors.top: parent.top""", f"""    Rectangle {{
        visible: root.isSelected
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5
        anchors.horizontalCenter: parent.horizontalCenter
        width: 16
        height: 3
        radius: 1.5
        color: "{ACCENT}"
    }}

    SourceBadge {{
        anchors.top: parent.top""")
sub(G, """        source: root.item?.type === "app" ? (root.item.source || "") : \"\"""", """        source: \"\"""")
sub(G, "iconColor: root.isSelected ? Theme.primary : Theme.surfaceText", "iconColor: Theme.surfaceText")
sub(G, "color: root.isSelected ? Theme.primary : Theme.surfaceText", "color: Theme.surfaceText")

C = "Controller.qml"
sub(C, "    property int gridColumns: SettingsData.appLauncherGridColumns\n",
    "    property int gridColumns: viewModeContext === \"appDrawer\" ? SettingsData.appLauncherGridColumns : 16\n")
sub("ResultsList.qml", "cellWidth * 0.75 : cellWidth + 24;", "cellWidth * 0.75 : Math.min(cellWidth + 24, 108);")

L = "LauncherContent.qml"
# la lista no se oculta de golpe al cerrar: se va con el fade
sub(L, "                    return root.parentModal.isClosing ? 0 : 1;", "                    return 1;")
sub(L, "                id: hintsRow\n", "                id: hintsRow\n                visible: false\n")
# pie sin franja de otro color
sub(L, """                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                radius: Theme.cornerRadius""", """                color: "transparent"
                radius: Theme.cornerRadius""")
# botones de modo: cápsula tenue en vez de botón sólido
sub(L, """                        radius: Theme.cornerRadius
                        color: controller.searchMode === modelData.id ? Theme.buttonBg :""",
    """                        radius: height / 2
                        color: controller.searchMode === modelData.id ? Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.08) :""")
sub(L, "color: controller.searchMode === modelData.id ? Theme.buttonText : Theme.surfaceVariantText",
    "color: controller.searchMode === modelData.id ? Theme.surfaceText : Theme.surfaceVariantText")
sub(L, "color: controller.searchMode === modelData.id ? Theme.buttonText : Theme.surfaceText",
    "color: controller.searchMode === modelData.id ? Theme.surfaceText : Theme.surfaceVariantText")
# búsqueda sin borde, fondo apenas marcado
sub(L, """                leftIconFocusedColor: Theme.primary
                showClearButton: true""", """                leftIconFocusedColor: Theme.surfaceText
                backgroundColor: Qt.rgba(1, 1, 1, 0.04)
                normalBorderColor: "transparent"
                focusedBorderColor: Qt.rgba(1, 1, 1, 0.10)
                focusedBorderWidth: 1
                showClearButton: true""")

for f, s in files.items():
    open(os.path.join(d, f), "w").write(s)
