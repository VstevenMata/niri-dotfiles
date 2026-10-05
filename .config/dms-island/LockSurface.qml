pragma ComponentBehavior: Bound

// Reemplazo de Modules/Lock/LockSurface.qml de DMS (lo copia ~/.local/bin/dms-run-custom).
// Misma interfaz que el original: Lock.qml, Pam.qml y el WlSessionLock siguen siendo los de DMS.
// Muestra Island.qml; si Island no carga, vuelve al contenido original de DMS para no dejarte fuera.

import QtQuick
import Quickshell.Wayland
import qs.Common

FocusScope {
    id: root

    required property WlSessionLock lock
    required property var pam
    required property string sharedPasswordBuffer
    required property string screenName
    required property bool isLocked

    signal passwordChanged(string newPassword)
    signal unlockRequested

    Loader {
        id: island
        anchors.fill: parent
        focus: status === Loader.Ready
        source: "Island.qml"
        onLoaded: {
            item.locked = true;
            item.pam = root.pam;
            item.sessionLock = root.lock;
            item.screenName = Qt.binding(() => root.screenName);
            item.passwordEdited.connect(t => root.passwordChanged(t));
            item.reset();
        }
    }

    Loader {
        anchors.fill: parent
        active: island.status === Loader.Error
        focus: active
        sourceComponent: LockScreenContent {
            demoMode: false
            sessionLock: root.lock
            pam: root.pam
            passwordBuffer: root.sharedPasswordBuffer
            screenName: root.screenName
            focus: true
            onUnlockRequested: root.unlockRequested()
            onPasswordEdited: text => root.passwordChanged(text)
        }
    }

    Component.onCompleted: forceActiveFocus()

    onIsLockedChanged: {
        if (isLocked && island.item) {
            island.item.reset();
            island.item.forceActiveFocus();
        }
    }
}
