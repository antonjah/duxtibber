import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: button

    property string text
    property bool flat: false

    signal clicked

    implicitWidth: label.width + Theme.spacingL * 2
    implicitHeight: label.height + Theme.spacingS * 2
    radius: height / 2
    color: flat ? "transparent" : Qt.alpha(Theme.primary, mouse.containsMouse ? 0.28 : 0.18)

    StyledText {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: Theme.primary
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        font.underline: button.flat && mouse.containsMouse
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
