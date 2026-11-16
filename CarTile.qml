import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import "Tibber.js" as Tibber

Rectangle {
    id: tile

    property var car: null

    signal disconnect

    readonly property color accent: !car ? Theme.primary : car.charging ? Theme.success : car.soc < 20 ? Theme.error : Theme.primary
    readonly property string status: !car ? "" : !car.online ? I18n.trFor("duxTibber", "Offline") : car.charging ? I18n.trFor("duxTibber", "Charging") : car.plugged ? I18n.trFor("duxTibber", "Plugged in") : I18n.trFor("duxTibber", "Not plugged in")
    readonly property string statusIcon: !car ? "" : car.charging ? "bolt" : car.plugged ? "power" : "power_off"
    readonly property string badgeIcon: !car ? "" : car.charging ? "battery_charging_full" : car.soc >= 95 ? "battery_full" : "battery_" + Math.round(car.soc / 100 * 6) + "_bar"

    implicitHeight: body.height + Theme.spacingL * 2
    radius: Theme.cornerRadius * 1.5
    color: Theme.surfaceContainerHigh

    function seen() {
        if (!car || !car.lastSeen)
            return ""
        const days = Tibber.daysAgo(car.lastSeen, Date.now())
        const at = Qt.formatTime(new Date(car.lastSeen), "HH:mm")
        return days <= 0 ? I18n.trFor("duxTibber", "Seen %1").arg(at) : days === 1 ? I18n.trFor("duxTibber", "Seen yesterday %1").arg(at) : I18n.trFor("duxTibber", "Seen %1 days ago").arg(days)
    }

    Column {
        id: body
        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingM

        Item {
            width: parent.width
            height: badge.height

            Rectangle {
                id: badge
                width: 44
                height: 44
                radius: width / 2
                color: Qt.alpha(tile.accent, 0.16)

                DIcon {
                    anchors.centerIn: parent
                    name: tile.badgeIcon
                    size: Theme.iconSize
                    color: tile.accent
                }
            }

            Column {
                anchors.left: badge.right
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: tile.car ? tile.car.brand + " " + tile.car.name : ""
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                }

                Row {
                    spacing: Theme.spacingXS

                    DIcon {
                        name: tile.statusIcon
                        size: Theme.fontSizeSmall
                        color: tile.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: tile.status
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: tile.car ? tile.car.soc + " %" : ""
                color: tile.accent
                font.pixelSize: Theme.fontSizeXLarge + 6
                font.weight: Font.Bold
            }
        }

        Item {
            width: parent.width
            height: 14

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 8
                radius: height / 2
                color: Qt.alpha(Theme.surfaceText, 0.12)

                Rectangle {
                    width: tile.car ? track.width * Math.min(100, tile.car.soc) / 100 : 0
                    height: parent.height
                    radius: height / 2
                    color: tile.accent
                }
            }

            Rectangle {
                visible: !!tile.car && tile.car.target > 0
                x: tile.car ? track.width * tile.car.target / 100 - 1 : 0
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: 14
                radius: 1
                color: Qt.alpha(Theme.surfaceText, 0.8)
            }
        }

        Item {
            width: parent.width
            height: rangeText.height

            StyledText {
                id: rangeText
                text: tile.car ? I18n.trFor("duxTibber", "%1 km range").arg(tile.car.rangeKm) : ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }

            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: tile.car ? I18n.trFor("duxTibber", "Target %1 %").arg(tile.car.target) : ""
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Item {
            width: parent.width
            height: Math.max(seenText.height, unlink.height)

            StyledText {
                id: seenText
                anchors.verticalCenter: parent.verticalCenter
                text: tile.seen()
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            LinkButton {
                id: unlink
                anchors.right: parent.right
                flat: true
                text: I18n.trFor("duxTibber", "Disconnect")
                onClicked: tile.disconnect()
            }
        }
    }
}
