import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "duxTibber"

    StyledText {
        width: parent.width
        text: I18n.trFor("duxTibber", "With a Tibber token (developer.tibber.com) the widget shows your own home and prices. Put the token in a file and point to it below; the token itself is never stored in these settings. Without a token it shows free spot prices for the price area chosen below, or Tibber's demo data if none is chosen.")
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("duxTibber", "Values set in ~/.config/tibber/config.json (for example by home-manager) override the settings below.")
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "tokenFile"
        label: I18n.trFor("duxTibber", "Token file")
        description: I18n.trFor("duxTibber", "Path to a file containing only your Tibber access token")
        placeholder: "~/.config/tibber/token"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "homeId"
        label: I18n.trFor("duxTibber", "Home ID")
        description: I18n.trFor("duxTibber", "Optional. Leave empty to use the first home with a subscription")
        placeholder: ""
        defaultValue: ""
    }

    SelectionSetting {
        settingKey: "priceArea"
        label: I18n.trFor("duxTibber", "Price area (no token)")
        description: I18n.trFor("duxTibber", "Elprisområde for free spot prices without a token. Ignored when a token is set. Spot prices exclude grid fees, tax and markup, so they differ from your Tibber bill")
        options: [
            { label: I18n.trFor("duxTibber", "None (demo data)"), value: "" },
            { label: "SE1 – Luleå", value: "SE1" },
            { label: "SE2 – Sundsvall", value: "SE2" },
            { label: "SE3 – Stockholm", value: "SE3" },
            { label: "SE4 – Malmö", value: "SE4" },
            { label: "NO1 – Oslo", value: "NO1" },
            { label: "NO2 – Kristiansand", value: "NO2" },
            { label: "NO3 – Trondheim", value: "NO3" },
            { label: "NO4 – Tromsø", value: "NO4" },
            { label: "NO5 – Bergen", value: "NO5" }
        ]
        defaultValue: ""
    }

    SelectionSetting {
        settingKey: "priceUnit"
        label: I18n.trFor("duxTibber", "Price unit")
        description: I18n.trFor("duxTibber", "Show prices in whole currency (1.23 SEK/kWh) or in the minor unit (123 öre/kWh)")
        options: [
            { label: I18n.trFor("duxTibber", "Whole currency (kr, €)"), value: "major" },
            { label: I18n.trFor("duxTibber", "Minor unit (öre, øre, ct)"), value: "minor" }
        ]
        defaultValue: "major"
    }

    SelectionSetting {
        settingKey: "refreshMinutes"
        label: I18n.trFor("duxTibber", "Refresh interval")
        description: I18n.trFor("duxTibber", "How often to ask Tibber for prices (the limit is 100 requests per 5 minutes)")
        options: [
            { label: "5 min", value: "5" },
            { label: "15 min", value: "15" },
            { label: "30 min", value: "30" },
            { label: "60 min", value: "60" }
        ]
        defaultValue: "15"
    }
}
