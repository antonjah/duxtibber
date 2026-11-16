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

    ToggleSetting {
        settingKey: "showUnit"
        label: I18n.trFor("duxTibber", "Show unit after prices")
        description: I18n.trFor("duxTibber", "Append the unit to prices in the bar and the popup (200 öre instead of 200)")
        defaultValue: true
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

    StyledText {
        width: parent.width
        text: I18n.trFor("duxTibber", "Car")
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
    }

    ToggleSetting {
        settingKey: "showCar"
        label: I18n.trFor("duxTibber", "Show my car")
        description: I18n.trFor("duxTibber", "Show the charge of your connected car in the popup. This needs a free Tibber API client; the popup guides you through it.")
        defaultValue: false
    }

    StringSetting {
        settingKey: "carName"
        label: I18n.trFor("duxTibber", "Which car")
        description: I18n.trFor("duxTibber", "Name, model or ID of the car to show. Leave empty to use the first car in your account")
        placeholder: ""
        defaultValue: ""
    }

    StringSetting {
        settingKey: "carClientId"
        label: I18n.trFor("duxTibber", "Client ID")
        description: I18n.trFor("duxTibber", "From data-api.tibber.com/clients/manage (redirect address http://localhost:8765/callback). Press Enter to save")
        placeholder: ""
        defaultValue: ""
    }

    StringSetting {
        settingKey: "carSecretFile"
        label: I18n.trFor("duxTibber", "Client secret file")
        description: I18n.trFor("duxTibber", "Path to a file containing only the client secret; the secret itself is never stored in these settings")
        placeholder: "~/.config/tibber/data-api-secret"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "carRedirect"
        label: I18n.trFor("duxTibber", "Address after login")
        description: I18n.trFor("duxTibber", "After approving the Tibber login the browser shows a page that cannot connect. Paste its address here and press Enter; it is used once and then cleared")
        placeholder: "http://localhost:8765/callback?code=…"
        defaultValue: ""
    }
}
