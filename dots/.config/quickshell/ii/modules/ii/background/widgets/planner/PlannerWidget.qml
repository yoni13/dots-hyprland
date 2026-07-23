pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

AbstractBackgroundWidget {
    id: root

    configEntryName: "planner"
    width: Math.max(600, Math.min(700, screenWidth - 48))
    height: 456
    draggable: placementStrategy === "free" && !taskInput.hovered && !taskInput.activeFocus

    property date today: new Date()
    property date displayedMonth: new Date(today.getFullYear(), today.getMonth(), 1)
    property date selectedDate: today
    readonly property var localPendingTasks: Todo.list.map((task, index) => ({
            "kind": "task",
            "source": "local",
            "content": task.content,
            "done": task.done,
            "originalIndex": index
        })).filter(task => !task.done)
    readonly property var googlePendingTasks: !GoogleWorkspace.enabled ? [] : GoogleWorkspace.tasks.map(task => ({
            "kind": "task",
            "source": "google",
            "content": task.title,
            "remoteTask": task
        })).filter(task => task.remoteTask.status !== "completed")
    readonly property var pendingTasks: localPendingTasks.concat(googlePendingTasks)
    readonly property var selectedEvents: eventsForDate(selectedDate).map(event => ({
            "kind": "event",
            "source": "google",
            "content": event.title,
            "event": event
        }))
    readonly property var agendaItems: selectedEvents.concat(pendingTasks)

    function shiftMonth(offset) {
        displayedMonth = new Date(displayedMonth.getFullYear(), displayedMonth.getMonth() + offset, 1);
    }

    function calendarDate(index) {
        const firstWeekday = displayedMonth.getDay();
        return new Date(displayedMonth.getFullYear(), displayedMonth.getMonth(), index - firstWeekday + 1);
    }

    function sameDay(first, second) {
        return first.getFullYear() === second.getFullYear()
            && first.getMonth() === second.getMonth()
            && first.getDate() === second.getDate();
    }

    function dateKey(date) {
        const pad = value => String(value).padStart(2, "0");
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    function eventsForDate(date) {
        const key = dateKey(date);
        return GoogleWorkspace.enabled ? GoogleWorkspace.events.filter(event => event.startDate === key) : [];
    }

    function eventTime(event) {
        if (event.allDay)
            return Translation.tr("All day");
        return new Date(event.start).toLocaleTimeString(Qt.locale(), "HH:mm");
    }

    function completeTask(task) {
        if (task.source === "google")
            GoogleWorkspace.completeTask(task.remoteTask);
        else
            Todo.markDone(task.originalIndex);
    }

    function deleteTask(task) {
        if (task.source === "google")
            GoogleWorkspace.deleteTask(task.remoteTask);
        else
            Todo.deleteItem(task.originalIndex);
    }

    function addTask() {
        const content = taskInput.text.trim();
        if (content.length === 0)
            return;
        if (GoogleWorkspace.enabled && GoogleWorkspace.connected)
            GoogleWorkspace.addTask(content);
        else
            Todo.addTask(content);
        taskInput.clear();
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20

            ColumnLayout {
                Layout.preferredWidth: 304
                Layout.minimumWidth: 304
                Layout.maximumWidth: 304
                Layout.fillHeight: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: root.displayedMonth.toLocaleDateString(Qt.locale(), "MMMM")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.title
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            text: root.displayedMonth.getFullYear()
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    PlannerIconButton {
                        iconName: "chevron_left"
                        accessibleName: Translation.tr("Previous month")
                        onClicked: root.shiftMonth(-1)
                    }
                    PlannerIconButton {
                        iconName: "today"
                        accessibleName: Translation.tr("Current month")
                        onClicked: {
                            root.displayedMonth = new Date(root.today.getFullYear(), root.today.getMonth(), 1);
                            root.selectedDate = root.today;
                        }
                    }
                    PlannerIconButton {
                        iconName: "chevron_right"
                        accessibleName: Translation.tr("Next month")
                        onClicked: root.shiftMonth(1)
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: 2

                    Repeater {
                        model: 7
                        delegate: StyledText {
                            required property int index
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 28
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: new Date(2024, 0, 7 + index).toLocaleDateString(Qt.locale(), "ddd").slice(0, 1)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }
                    }

                    Repeater {
                        model: 42
                        delegate: RippleButton {
                            id: dayButton
                            required property int index
                            readonly property date dateValue: root.calendarDate(index)
                            readonly property bool inDisplayedMonth: dateValue.getMonth() === root.displayedMonth.getMonth()
                            readonly property bool isToday: root.sameDay(dateValue, root.today)
                            readonly property bool isSelected: root.sameDay(dateValue, root.selectedDate)
                            readonly property var dayEvents: root.eventsForDate(dateValue)

                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            toggled: isSelected
                            buttonRadius: 20
                            buttonRadiusPressed: 14
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            colBackgroundToggled: Appearance.colors.colPrimary
                            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                            onClicked: {
                                root.selectedDate = dateValue;
                                if (!inDisplayedMonth)
                                    root.displayedMonth = new Date(dateValue.getFullYear(), dateValue.getMonth(), 1);
                            }

                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: dayButton.dateValue.getDate()
                                color: dayButton.isSelected ? Appearance.colors.colOnPrimary
                                    : dayButton.inDisplayedMonth ? Appearance.colors.colOnLayer1
                                    : Appearance.colors.colSubtext
                                opacity: dayButton.inDisplayedMonth || dayButton.isSelected ? 1 : 0.5
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: dayButton.isToday || dayButton.isSelected ? Font.DemiBold : Font.Normal
                            }

                            Rectangle {
                                visible: dayButton.isToday && !dayButton.isSelected && dayButton.dayEvents.length === 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                width: 4
                                height: 4
                                radius: 2
                                color: Appearance.colors.colPrimary
                            }

                            Rectangle {
                                visible: dayButton.dayEvents.length > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                width: dayButton.dayEvents.length > 1 ? 10 : 5
                                height: 5
                                radius: 3
                                color: dayButton.isSelected ? Appearance.colors.colOnPrimary
                                    : dayButton.dayEvents[0]?.color || Appearance.colors.colTertiary
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 250
                    Layout.maximumWidth: 250
                    Layout.preferredHeight: 56
                    Layout.alignment: Qt.AlignHCenter
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSecondaryContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: root.selectedDate.toLocaleDateString(Qt.locale(), "dddd")
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: root.selectedDate.toLocaleDateString(Qt.locale(), "MMMM d")
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                        }
                        MaterialSymbol {
                            text: "calendar_month"
                            color: Appearance.colors.colOnSecondaryContainer
                            iconSize: 28
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: Appearance.colors.colOutlineVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 260
                Layout.fillHeight: true
                spacing: 10

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Agenda")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.title
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            text: Translation.tr("%1 remaining").arg(root.pendingTasks.length)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: 36
                        height: 36
                        radius: 18
                        color: Appearance.colors.colPrimaryContainer
                        StyledText {
                            id: taskCount
                            anchors.centerIn: parent
                            text: root.pendingTasks.length
                            color: Appearance.colors.colOnPrimaryContainer
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: taskList
                        anchors.fill: parent
                        spacing: 6
                        clip: true
                        model: ScriptModel {
                            values: root.agendaItems
                        }
                        delegate: Rectangle {
                            id: taskDelegate
                            required property var modelData
                            width: ListView.view.width
                            implicitHeight: Math.max(48, taskText.implicitHeight + 16)
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                spacing: 2

                                PlannerIconButton {
                                    visible: taskDelegate.modelData.kind === "task"
                                    iconName: taskDelegate.modelData.source === "google" ? "add_task" : "radio_button_unchecked"
                                    accessibleName: Translation.tr("Mark task complete")
                                    enabled: taskDelegate.modelData.source !== "google" || !GoogleWorkspace.busy
                                    onClicked: root.completeTask(taskDelegate.modelData)
                                }
                                MaterialSymbol {
                                    visible: taskDelegate.modelData.kind === "event"
                                    Layout.preferredWidth: 40
                                    text: "event"
                                    iconSize: 20
                                    color: taskDelegate.modelData.event?.color || Appearance.colors.colTertiary
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                StyledText {
                                    id: taskText
                                    Layout.fillWidth: true
                                    text: taskDelegate.modelData.kind === "event"
                                        ? `${root.eventTime(taskDelegate.modelData.event)}  ${taskDelegate.modelData.content}`
                                        : taskDelegate.modelData.content
                                    color: Appearance.colors.colOnLayer2
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                                PlannerIconButton {
                                    visible: taskDelegate.modelData.kind === "task"
                                    iconName: "close"
                                    accessibleName: Translation.tr("Delete task")
                                    enabled: taskDelegate.modelData.source !== "google" || !GoogleWorkspace.busy
                                    onClicked: root.deleteTask(taskDelegate.modelData)
                                }
                            }
                        }

                        add: Transition {
                            NumberAnimation {
                                properties: "opacity,scale"
                                from: 0
                                to: 1
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.agendaItems.length === 0
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "task_alt"
                            iconSize: 42
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("All clear")
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            text: Translation.tr("Add something for later")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: 18
                    color: Appearance.m3colors.m3surfaceContainerHigh
                    border.width: taskInput.activeFocus ? 2 : 1
                    border.color: taskInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                    Behavior on border.color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4

                        TextField {
                            id: taskInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            leftPadding: 10
                            rightPadding: 6
                            placeholderText: Translation.tr("Add a task")
                            placeholderTextColor: Appearance.colors.colSubtext
                            color: Appearance.colors.colOnLayer1
                            selectionColor: Appearance.colors.colPrimary
                            selectedTextColor: Appearance.colors.colOnPrimary
                            font {
                                family: Appearance.font.family.main
                                pixelSize: Appearance.font.pixelSize.small
                                variableAxes: Appearance.font.variableAxes.main
                            }
                            background: Item {}
                            onAccepted: root.addTask()
                        }
                        RippleButton {
                            Layout.preferredWidth: 48
                            Layout.minimumWidth: 48
                            Layout.maximumWidth: 48
                            Layout.preferredHeight: 48
                            Layout.minimumHeight: 48
                            Layout.maximumHeight: 48
                            buttonRadius: 15
                            buttonRadiusPressed: 12
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: root.addTask()
                            contentItem: MaterialSymbol {
                                text: "add"
                                iconSize: 24
                                color: Appearance.colors.colOnPrimary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
        }
    }

    component PlannerIconButton: RippleButton {
        required property string iconName
        property string accessibleName
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: 20
        buttonRadiusPressed: 14
        Accessible.name: accessibleName
        contentItem: MaterialSymbol {
            text: parent.iconName
            iconSize: 20
            color: Appearance.colors.colOnLayer1
        }
    }
}
