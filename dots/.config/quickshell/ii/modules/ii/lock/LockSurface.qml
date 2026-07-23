import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar

MouseArea {
    id: root

    required property LockContext context
    property bool active: false
    property bool ctrlHeld: false
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower
    readonly property string authStatus: {
        if (root.context.unlockInProgress)
            return Translation.tr("Checking credentials...");
        if (GlobalStates.screenUnlockFailed)
            return Translation.tr("That password did not work");
        if (root.context.targetAction === LockContext.ActionEnum.Poweroff)
            return Translation.tr("Authenticate to shut down");
        if (root.context.targetAction === LockContext.ActionEnum.Reboot)
            return Translation.tr("Authenticate to restart");
        if (root.context.fingerprintsConfigured)
            return Translation.tr("Use your password or fingerprint");
        return Translation.tr("Welcome back");
    }

    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: root.forceFieldFocus()
    onPositionChanged: root.forceFieldFocus()

    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control)
            root.ctrlHeld = true;
        if (event.key === Qt.Key_Escape) {
            root.context.currentText = "";
            root.context.resetTargetAction();
        }
        root.forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control)
            root.ctrlHeld = false;
        root.forceFieldFocus();
    }

    Connections {
        target: root.context
        function onShouldReFocus() {
            root.forceFieldFocus();
        }
    }

    Component.onCompleted: {
        root.forceFieldFocus();
        authCard.opacity = 1;
        authCard.scale = 1;
    }

    Rectangle {
        id: authCard

        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Math.max(28, parent.height * 0.045)
        }
        width: Math.min(680, parent.width - 40)
        implicitHeight: cardContent.implicitHeight + 40
        radius: 32
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        opacity: 0
        scale: 0.92

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: cardContent

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 20
            }
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    radius: 18
                    color: Appearance.colors.colPrimaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "person"
                        fill: 1
                        iconSize: 28
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        text: SystemInfo.username
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        text: root.authStatus
                        color: GlobalStates.screenUnlockFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        animateChange: true
                    }
                }

                StatusChip {
                    iconName: "keyboard_alt"
                    label: HyprlandXkb.currentLayoutCode.toUpperCase()
                }

                StatusChip {
                    visible: Battery.available
                    iconName: Battery.isCharging ? "bolt" : "battery_android_full"
                    label: `${Math.round(Battery.percentage * 100)}%`
                    alert: Battery.isLow && !Battery.isCharging
                }
            }

            Rectangle {
                id: passwordContainer

                Layout.fillWidth: true
                Layout.preferredHeight: 60
                radius: 20
                color: Appearance.m3colors.m3surfaceContainerHighest
                border.width: passwordBox.activeFocus ? 2 : 1
                border.color: GlobalStates.screenUnlockFailed ? Appearance.colors.colError
                    : passwordBox.activeFocus ? Appearance.colors.colPrimary
                    : Appearance.colors.colOutlineVariant
                clip: true

                Behavior on border.color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                ErrorShakeAnimation {
                    id: wrongPasswordShakeAnim
                    target: passwordContainer
                }

                Connections {
                    target: GlobalStates
                    function onScreenUnlockFailedChanged() {
                        if (GlobalStates.screenUnlockFailed)
                            wrongPasswordShakeAnim.restart();
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    Loader {
                        Layout.leftMargin: 10
                        Layout.preferredWidth: 28
                        active: root.context.fingerprintsConfigured
                        visible: active
                        sourceComponent: MaterialSymbol {
                            text: "fingerprint"
                            fill: 1
                            iconSize: 24
                            color: Appearance.colors.colPrimary
                        }
                    }

                    TextField {
                        id: passwordBox

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        leftPadding: root.context.fingerprintsConfigured ? 4 : 14
                        rightPadding: 8
                        enabled: !root.context.unlockInProgress
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                        placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Try your password again") : Translation.tr("Enter password")
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: materialShapeChars ? "transparent" : Appearance.colors.colOnLayer1
                        selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
                        selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer
                        font {
                            family: Appearance.font.family.main
                            pixelSize: Appearance.font.pixelSize.normal
                            variableAxes: Appearance.font.variableAxes.main
                        }
                        background: Item {}
                        property bool materialShapeChars: Config.options.lock.materialShapeChars

                        onTextChanged: root.context.currentText = text
                        onAccepted: root.context.tryUnlock(root.ctrlHeld)
                        Keys.onPressed: root.context.resetClearTimer()

                        Connections {
                            target: root.context
                            function onCurrentTextChanged() {
                                passwordBox.text = root.context.currentText;
                            }
                        }

                        Loader {
                            active: passwordBox.materialShapeChars
                            anchors {
                                fill: parent
                                leftMargin: passwordBox.leftPadding
                                rightMargin: passwordBox.rightPadding
                            }
                            sourceComponent: PasswordChars {
                                length: root.context.currentText.length
                                selectionStart: passwordBox.selectionStart
                                selectionEnd: passwordBox.selectionEnd
                                cursorPosition: passwordBox.cursorPosition
                            }
                        }
                    }

                    RippleButton {
                        id: confirmButton

                        Layout.preferredWidth: 52
                        Layout.minimumWidth: 52
                        Layout.maximumWidth: 52
                        Layout.preferredHeight: 52
                        Layout.minimumHeight: 52
                        Layout.maximumHeight: 52
                        enabled: !root.context.unlockInProgress
                        buttonRadius: 17
                        buttonRadiusPressed: 13
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        onClicked: root.context.tryUnlock(root.ctrlHeld)

                        contentItem: MaterialSymbol {
                            text: {
                                if (root.context.unlockInProgress)
                                    return "progress_activity";
                                if (root.context.targetAction === LockContext.ActionEnum.Poweroff)
                                    return "power_settings_new";
                                if (root.context.targetAction === LockContext.ActionEnum.Reboot)
                                    return "restart_alt";
                                return root.ctrlHeld ? "coffee" : "arrow_forward";
                            }
                            iconSize: 24
                            color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            animateChange: true
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: root.context.fingerprintsConfigured ? "touch_app" : "lock"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.context.fingerprintsConfigured
                        ? Translation.tr("Fingerprint sensor is ready")
                        : Translation.tr("Press Enter to unlock")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                Bar.SysTray {
                    Layout.alignment: Qt.AlignVCenter
                    showSeparator: false
                    showOverflowMenu: false
                    pinnedItems: SystemTray.items.values.filter(item => item.id === "Fcitx")
                    visible: pinnedItems.length > 0
                }

                LockActionButton {
                    iconName: "dark_mode"
                    accessibleName: Translation.tr("Suspend")
                    onClicked: Session.suspend()
                }
                PasswordGuardedActionButton {
                    iconName: "restart_alt"
                    accessibleName: Translation.tr("Restart")
                    targetAction: LockContext.ActionEnum.Reboot
                }
                PasswordGuardedActionButton {
                    iconName: "power_settings_new"
                    accessibleName: Translation.tr("Shut down")
                    targetAction: LockContext.ActionEnum.Poweroff
                }
            }
        }
    }

    component StatusChip: Rectangle {
        id: statusChip

        required property string iconName
        required property string label
        property bool alert: false

        Layout.preferredHeight: 36
        implicitWidth: chipRow.implicitWidth + 20
        radius: 18
        color: alert ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                text: statusChip.iconName
                iconSize: 18
                fill: 1
                color: statusChip.alert ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
            }
            StyledText {
                text: statusChip.label
                color: statusChip.alert ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
            }
        }
    }

    component LockActionButton: RippleButton {
        id: lockActionButton

        required property string iconName
        property string accessibleName

        Layout.preferredWidth: 42
        Layout.preferredHeight: 42
        buttonRadius: 21
        buttonRadiusPressed: 15
        Accessible.name: accessibleName

        contentItem: MaterialSymbol {
            text: lockActionButton.iconName
            iconSize: 20
            color: lockActionButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component PasswordGuardedActionButton: LockActionButton {
        id: guardedButton

        required property var targetAction
        toggled: root.context.targetAction === guardedButton.targetAction

        onClicked: {
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedButton.targetAction);
                return;
            }
            if (root.context.targetAction === guardedButton.targetAction)
                root.context.resetTargetAction();
            else
                root.context.targetAction = guardedButton.targetAction;
            root.context.shouldReFocus();
        }
    }
}
