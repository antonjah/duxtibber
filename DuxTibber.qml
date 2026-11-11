import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "Tibber.js" as Tibber

PluginComponent {
    id: root

    layerNamespacePlugin: "tibber"

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string tokenFile: (setting("tokenFile", "") || (configHome + "/tibber/token")).replace(/^~/, Quickshell.env("HOME"))
    readonly property string homeId: setting("homeId", "")
    readonly property int refreshMinutes: Math.max(5, Number(setting("refreshMinutes", 0)) || 15)
    // ponytail: overridable only so tests can point at a mock server.
    readonly property string apiUrl: pluginData.apiUrl || Tibber.API_URL
    readonly property string priceArea: setting("priceArea", "")
    readonly property bool minor: setting("priceUnit", "") === "minor"

    // Declared settings (e.g. written by home-manager) win over the settings page.
    property var declared: ({})

    function setting(key, fallback) {
        const v = declared[key] !== undefined ? declared[key] : pluginData[key]
        return v !== undefined && v !== null ? v : fallback
    }

    function readDeclared() {
        try {
            declared = JSON.parse(declaredView.text())
        } catch (e) {
            declared = ({})
        }
    }

    FileView {
        id: declaredView
        path: root.configHome + "/tibber/config.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.readDeclared()
        onLoadFailed: root.declared = ({})
        onFileChanged: reload()
    }

    Component.onCompleted: readDeclared()

    // One shared state for every bar instance (one per screen) so only one request goes out.
    PluginGlobalVar {
        id: shared
        varName: "state"
        defaultValue: ({ model: null, error: "", nextAt: 0, fetching: 0, demo: true, updatedAt: 0 })
    }

    readonly property var st: shared.value
    property real now: Date.now()
    readonly property var cur: st.model ? Tibber.current(st.model.prices, now) : null
    readonly property color levelColor: !cur && st.error ? Theme.error : Theme[Tibber.levelColor(cur ? cur.level : "")]
    readonly property string priceText: cur ? Tibber.fmtPrice(cur.total, minor) : (st.error ? "!" : "…")

    FileView {
        id: tokenView
        path: root.tokenFile
        blockLoading: true
        watchChanges: true
        printErrors: false
    }

    function readToken() {
        try {
            return tokenView.text().trim()
        } catch (e) {
            return ""
        }
    }

    function finish(patch) {
        shared.set(Object.assign({}, shared.value, patch, { fetching: 0 }))
    }

    function request(method, url, headers, body, cb) {
        const x = new XMLHttpRequest()
        x.open(method, url)
        for (const k in headers)
            x.setRequestHeader(k, headers[k])
        x.onreadystatechange = () => {
            if (x.readyState === XMLHttpRequest.DONE)
                cb(x.status, x.responseText)
        }
        x.send(body)
    }

    function httpError(status) {
        if (status === 401)
            return I18n.trFor("duxTibber", "Invalid token")
        if (status === 0)
            return I18n.trFor("duxTibber", "Offline")
        return I18n.trFor("duxTibber", "Server returned HTTP %1").arg(status)
    }

    // m is the parsed model when status is 200, otherwise null.
    function result(demo, status, m) {
        const t = Date.now()
        const error = status === 200 ? (m.error || "") : httpError(status)
        const ok = !error
        finish({
            model: ok ? m : shared.value.model,
            error: error,
            demo: demo,
            updatedAt: ok ? t : shared.value.updatedAt,
            nextAt: Tibber.nextFetch(t, ok, refreshMinutes)
        })
    }

    function fetchTibber(token) {
        const demo = token === ""
        request("POST", apiUrl, {
            "Authorization": "Bearer " + (demo ? Tibber.DEMO_TOKEN : token),
            "Content-Type": "application/json"
        }, JSON.stringify({ query: Tibber.QUERY }), (status, text) => result(demo, status, status === 200 ? Tibber.parse(text, homeId) : null))
    }

    // Free spot prices for the chosen area; tomorrow is optional until it is published (~13:00).
    function fetchSpot() {
        const base = pluginData.apiUrl ? pluginData.apiUrl.replace(/\/$/, "") : undefined
        const d = new Date()
        const next = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
        request("GET", Tibber.spotUrl(priceArea, d, base), {}, null, (status, today) => {
            if (status !== 200)
                return result(false, status, null)
            request("GET", Tibber.spotUrl(priceArea, next, base), {}, null, (status2, tomorrow) =>
                result(false, 200, Tibber.parseSpot(priceArea, today, status2 === 200 ? tomorrow : null)))
        })
    }

    function refresh() {
        const s = shared.value
        // A request stuck for over a minute is treated as dead.
        if (s.fetching && Date.now() - s.fetching < 60000)
            return
        shared.set(Object.assign({}, s, { fetching: Date.now() }))

        const token = readToken()
        if (token === "" && priceArea)
            fetchSpot()
        else
            fetchTibber(token)
    }

    function refreshIfDue() {
        now = Date.now()
        if (now >= st.nextAt)
            refresh()
    }

    // Changing where prices come from should not wait for the next interval.
    // The delay lets FileView load a changed token path before it is read.
    readonly property string fetchKey: tokenFile + "|" + homeId + "|" + priceArea
    onFetchKeyChanged: {
        shared.set(Object.assign({}, shared.value, { nextAt: 0 }))
        keyDebounce.restart()
    }

    Timer {
        id: keyDebounce
        interval: 500
        onTriggered: root.refreshIfDue()
    }

    // Current slot is recomputed from stored prices each minute; the network is only hit when due.
    Timer {
        interval: 60000
        repeat: true
        running: root.surfaceLive
        triggeredOnStart: true
        onTriggered: root.refreshIfDue()
    }

    pillRightClickAction: () => root.refresh()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: root.st.error && root.st.model ? "cloud_off" : "bolt"
                size: root.iconSize
                color: root.levelColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.priceText
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            DIcon {
                name: root.st.error && root.st.model ? "cloud_off" : "bolt"
                size: root.iconSize
                color: root.levelColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.priceText
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 460
    popoutHeight: 0

    popoutContent: Component {
        TibberPopout { plugin: root }
    }
}
