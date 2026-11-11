import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Rectangle {
    id: tile

    property string label
    property string icon
    property string value
    property string sub
    property color accent: Theme.surfaceText

    implicitHeight: body.height + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh

    Column {
        id: body
        x: Theme.spacingM
        y: Theme.spacingM
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingXS

        Item {
            width: parent.width
            height: Math.max(caption.height, glyph.height)

            StyledText {
                id: caption
                anchors.verticalCenter: parent.verticalCenter
                text: tile.label
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            DIcon {
                id: glyph
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                name: tile.icon
                size: Theme.iconSize - 6
                color: tile.accent
            }
        }

        StyledText {
            width: parent.width
            text: tile.value
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: tile.sub
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }
    }
}
