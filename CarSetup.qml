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
    property bool clientIdOk: false
    property bool secretOk: false
    property bool busy: false

    signal useAddress(string text)

    function openSettings() {
        Quickshell.execDetached(["dms", "ipc", "call", "settings", "openWith", "plugin:duxTibber"])
    }

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
                text: I18n.trFor("duxTibber", "2. Tell the plugin about it. It needs both of these:")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: [
                    { ok: card.clientIdOk, text: card.clientIdOk ? I18n.trFor("duxTibber", "Client ID entered") : I18n.trFor("duxTibber", "Client ID: enter it in the plugin settings and press Enter") },
                    { ok: card.secretOk, text: card.secretOk ? I18n.trFor("duxTibber", "Client secret file found") : I18n.trFor("duxTibber", "Client secret: save it in the file %1").arg(card.secretFile) }
                ]

                Row {
                    required property var modelData
                    spacing: Theme.spacingS

                    DIcon {
                        name: modelData.ok ? "check_circle" : "radio_button_unchecked"
                        size: 18
                        color: modelData.ok ? Theme.success : Theme.surfaceVariantText
                    }

                    StyledText {
                        width: body.width - 18 - Theme.spacingS
                        text: modelData.text
                        color: modelData.ok ? Theme.surfaceText : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }
                }
            }

            LinkButton {
                text: I18n.trFor("duxTibber", "Open plugin settings")
                onClicked: card.openSettings()
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("duxTibber", "This card moves on by itself once both are done.")
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
                text: I18n.trFor("duxTibber", "2. The browser then says it can't connect. That is expected. Click its address bar, select everything and copy it. The address starts with:")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: Tibber.CAR_REDIRECT + "?code=…"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.monoFontFamily
                wrapMode: Text.WrapAnywhere
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("duxTibber", "3. Come back here and click:")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            LinkButton {
                objectName: "useAddress"
                text: card.busy ? I18n.trFor("duxTibber", "Checking your login…") : I18n.trFor("duxTibber", "Use the address I copied")
                onClicked: if (!card.busy) card.useAddress(Quickshell.clipboardText)
            }

            StyledText {
                visible: card.message !== ""
                width: parent.width
                text: card.message
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: I18n.trFor("duxTibber", "Or paste the address in the plugin settings (Address after login) and press Enter.")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            LinkButton {
                flat: true
                text: I18n.trFor("duxTibber", "Open plugin settings")
                onClicked: card.openSettings()
            }
        }
    }
}
