import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import "Tibber.js" as Tibber

// Guides through everything the car tile needs; shown instead of the tile until the car is connected.
Rectangle {
    id: card

    property string mode: "setup"
    property string authUrl: ""
    property string message: ""
    property string error: ""
    property string carName: ""
    property var found: []
    property string secretFile: ""

    readonly property bool connecting: mode === "connect" || mode === "reconnect"
    readonly property color tint: mode === "error" || mode === "notfound" || mode === "nocar" || mode === "reconnect" ? Theme.warning : Theme.primary
    readonly property string glyph: mode === "reconnect" ? "link_off" : mode === "error" ? "error" : mode === "notfound" || mode === "nocar" ? "search_off" : mode === "loading" ? "hourglass_top" : "battery_charging_full"
    readonly property string title: {
        switch (mode) {
        case "setup": return I18n.trFor("duxTibber", "Show your car here")
        case "connect": return I18n.trFor("duxTibber", "Connect your Tibber account")
        case "reconnect": return I18n.trFor("duxTibber", "Tibber login expired")
        case "notfound": return I18n.trFor("duxTibber", "Car not found")
        case "nocar": return I18n.trFor("duxTibber", "No connected car")
        case "error": return I18n.trFor("duxTibber", "Car data unavailable")
        default: return I18n.trFor("duxTibber", "Loading car…")
        }
    }
    readonly property string plain: {
        switch (mode) {
        case "notfound": return I18n.trFor("duxTibber", "No car called \"%1\" in your account. Cars found: %2.").arg(carName).arg(found.join(", "))
        case "nocar": return I18n.trFor("duxTibber", "Pair your car in the Tibber app first.")
        case "error": return error
        default: return ""
        }
    }

    implicitHeight: body.height + Theme.spacingL * 2
    radius: Theme.cornerRadius * 1.5
    color: Theme.surfaceContainerHigh

    Column {
        id: body
        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingM

        Row {
            spacing: Theme.spacingM

            Rectangle {
                width: 36
                height: 36
                radius: width / 2
                color: Qt.alpha(card.tint, 0.16)

                DIcon {
                    anchors.centerIn: parent
                    name: card.glyph
                    size: Theme.iconSize - 4
                    color: card.tint
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: card.title
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
            }
        }

        StyledText {
            visible: card.plain !== ""
            width: parent.width
            text: card.plain
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        Column {
            visible: card.mode === "setup"
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: I18n.trFor("duxTibber", "1. Create a free API client at Tibber. Name it anything, tick the vehicle and home permissions, and use this redirect address:")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: Theme.spacingS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tibber.CAR_REDIRECT
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.monoFontFamily
                }

                LinkButton {
                    anchors.verticalCenter: parent.verticalCenter
                    flat: true
                    text: I18n.trFor("duxTibber", "Copy")
                    onClicked: Quickshell.clipboardText = Tibber.CAR_REDIRECT
                }
            }

            LinkButton {
                text: I18n.trFor("duxTibber", "Open Tibber's client page")
                onClicked: Qt.openUrlExternally(Tibber.CLIENTS_URL)
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("duxTibber", "2. In Settings → Plugins → Tibber → Car, enter the client ID, and save the client secret in the file %1.").arg(card.secretFile)
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }

        Column {
            visible: card.connecting
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: I18n.trFor("duxTibber", "1. Log in to Tibber and approve access to your vehicles.")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            LinkButton {
                text: I18n.trFor("duxTibber", "Open Tibber login")
                onClicked: Qt.openUrlExternally(card.authUrl)
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("duxTibber", "2. The browser then says it can't connect. That is expected: copy the address from its address bar and paste it in Settings → Plugins → Tibber → Car → Address after login.")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            StyledText {
                visible: card.message !== ""
                width: parent.width
                text: card.message
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }
    }
}
