import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    property bool hasEvents: false
    property color eventColor: Appearance.colors.colTertiary
    property string eventSummary: ""

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38; 
    implicitHeight: 38;

    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small
    
    contentItem: StyledText {
        anchors.fill: parent
        text: day
        horizontalAlignment: Text.AlignHCenter
        font.weight: bold ? Font.DemiBold : Font.Normal
        color: (isToday == 1) ? Appearance.m3colors.m3onPrimary : 
            (isToday == 0) ? Appearance.colors.colOnLayer1 : 
            Appearance.colors.colOutlineVariant

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Rectangle {
        visible: button.hasEvents
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        width: 5
        height: 5
        radius: 3
        color: button.isToday === 1 ? Appearance.colors.colOnPrimary : button.eventColor
    }

    StyledToolTip {
        visible: button.hasEvents && button.hovered
        text: button.eventSummary
    }
}
