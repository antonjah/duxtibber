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
    readonly property bool showUnit: String(setting("showUnit", true)) !== "false"

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

    Component.onCompleted: {
        readDeclared()
        hydrateCar()
    }

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
    readonly property string priceNumber: cur ? Tibber.fmtPrice(cur.total, minor) : (st.error ? "!" : "…")
    readonly property string unitText: cur && showUnit ? Tibber.unitShort(st.model.currency, minor) : ""
    readonly property string priceText: priceNumber + (unitText ? " " + unitText : "")

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
    // The previous 3 days give Tibber's trailing-average baseline; past days never change, so they are kept.
    function fetchSpot() {
        const base = pluginData.apiUrl ? pluginData.apiUrl.replace(/\/$/, "") : undefined
        const d = new Date()
        const url = n => Tibber.spotUrl(priceArea, new Date(d.getFullYear(), d.getMonth(), d.getDate() + n), base)
        const cache = shared.value.hist || ({})
        const hist = ({})
        const past = []

        const loadToday = () => {
            shared.set(Object.assign({}, shared.value, { hist: hist }))
            request("GET", url(0), {}, null, (status, today) => {
                if (status !== 200)
                    return result(false, status, null)
                request("GET", url(1), {}, null, (status2, tomorrow) =>
                    result(false, 200, Tibber.parseSpot(priceArea, today, status2 === 200 ? tomorrow : null, past, Date.now())))
            })
        }

        const loadPast = n => {
            if (n === 0)
                return loadToday()
            const u = url(n)
            const keep = text => {
                hist[u] = text
                past.push(text)
                loadPast(n + 1)
            }
            if (cache[u] !== undefined)
                return keep(cache[u])
            request("GET", u, {}, null, (status, text) => status === 200 ? keep(text) : loadPast(n + 1))
        }

        loadPast(-3)
    }

    function refresh() {
        const s = shared.value
        // A request stuck for over a minute is treated as dead.
        if (s.fetching && Date.now() - s.fetching < 60000)
            return
        shared.set(Object.assign({}, s, { fetching: Date.now(), key: fetchKey }))

        const token = readToken()
        if (token === "" && priceArea)
            fetchSpot()
        else
            fetchTibber(token)
    }

    // Optional car tile (Tibber Data API, OAuth). It fails quietly: prices never depend on it.
    readonly property bool showCar: String(setting("showCar", false)) === "true"
    readonly property string carName: String(setting("carName", ""))
    readonly property string carClientId: String(setting("carClientId", "")).trim()
    readonly property string carSecretFile: (String(setting("carSecretFile", "")) || (configHome + "/tibber/data-api-secret")).replace(/^~/, Quickshell.env("HOME"))
    readonly property string carRedirect: String(setting("carRedirect", ""))
    readonly property string dataApiUrl: pluginData.apiUrl ? pluginData.apiUrl.replace(/\/$/, "") : Tibber.DATA_HOST
    readonly property string authApiUrl: pluginData.apiUrl ? pluginData.apiUrl.replace(/\/$/, "") : Tibber.AUTH_HOST
    readonly property string carDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/duxtibber"
    readonly property string carAuthUrl: carClientId ? Tibber.authUrl(carClientId, Tibber.CAR_STATE, authApiUrl) : ""
    property bool carHasSecret: false
    // How often the open popout re-checks for a newly created secret file (a test seam).
    property int recheckMs: 2000

    PluginGlobalVar {
        id: carShared
        varName: "car"
        defaultValue: ({ data: null, found: [], tokens: null, revoked: false, fetched: false, error: "", message: "", loaded: false, nextAt: 0, fetching: 0, busy: 0 })
    }

    readonly property var car: carShared.value
    readonly property string carState: Tibber.carStatus({
        enabled: showCar, clientId: carClientId, hasSecret: carHasSecret, tokens: car.tokens, revoked: car.revoked,
        car: car.data, found: car.found, name: carName, error: car.error, fetched: car.fetched
    })

    // Tokens live in a private (0700) folder of their own: plugin_settings.json is world-readable.
    FileView {
        id: carStore
        path: root.carDir + "/car.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: secretView
        path: root.carSecretFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.carHasSecret = secretView.text().trim() !== ""
        onLoadFailed: root.carHasSecret = false
        onFileChanged: reload()
    }

    function setCar(patch) {
        carShared.set(Object.assign({}, carShared.value, patch))
    }

    function readSecret() {
        try {
            return secretView.text().trim()
        } catch (e) {
            return ""
        }
    }

    function hydrateCar() {
        carHasSecret = readSecret() !== ""
        if (carShared.value.loaded)
            return
        Quickshell.execDetached(["mkdir", "-m", "700", "-p", carDir])
        let tokens = null
        try {
            tokens = JSON.parse(carStore.text())
        } catch (e) {}
        setCar({ loaded: true, tokens: tokens && tokens.refresh_token ? tokens : null })
    }

    function saveTokens(t) {
        setCar({ tokens: t, revoked: false })
        carStore.setText(JSON.stringify(t))
    }

    function disconnectCar() {
        carStore.setText("")
        setCar({ tokens: null, data: null, found: [], revoked: false, fetched: false, error: "", message: "", nextAt: 0 })
    }

    // The browser address holds a one-time code. It comes from the card's clipboard button or from the
    // settings page (then it is cleared again once used).
    onCarRedirectChanged: if (carRedirect !== "") exchangeCar(carRedirect, true)

    // Creating the secret file while the popout is open must be noticed without waiting for the minute timer.
    function recheckCar() {
        secretView.reload()
    }

    function exchangeCar(address, fromSettings) {
        hydrateCar()
        if (carShared.value.busy && Date.now() - carShared.value.busy < 60000)
            return
        const finish = patch => {
            setCar(Object.assign({ busy: 0 }, patch))
            if (fromSettings)
                PluginService.savePluginData(pluginId, "carRedirect", "")
        }
        if (!String(address || "").trim())
            return finish({ message: I18n.trFor("duxTibber", "Nothing copied yet. Copy the whole address from the browser's address bar first.") })
        const r = Tibber.parseRedirect(address, Tibber.CAR_STATE)
        if (r.error)
            return finish({ message: r.error })
        const secret = readSecret()
        if (!carClientId || secret === "")
            return finish({ message: I18n.trFor("duxTibber", "Enter the client ID and the secret file first") })
        setCar({ busy: Date.now(), message: "" })
        request("POST", authApiUrl + "/connect/token", { "Content-Type": "application/x-www-form-urlencoded" },
            Tibber.tokenBody(carClientId, secret, { code: r.code }), (status, text) => {
            const t = Tibber.tokensFrom(text, Date.now())
            if (t.error)
                return finish({ message: t.error })
            saveTokens(t)
            finish({ message: "", nextAt: 0, fetched: false, error: "" })
            fetchCar()
        })
    }

    // The refresh token rotates: the new one is stored before the old one is forgotten.
    function refreshCarTokens(cb) {
        request("POST", authApiUrl + "/connect/token", { "Content-Type": "application/x-www-form-urlencoded" },
            Tibber.tokenBody(carClientId, readSecret(), { refresh: carShared.value.tokens.refresh_token }), (status, text) => {
            const t = Tibber.tokensFrom(text, Date.now(), carShared.value.tokens)
            if (t.error) {
                setCar({ revoked: t.revoked, error: t.revoked ? "" : t.error })
                return cb(null)
            }
            saveTokens(t)
            cb(t)
        })
    }

    function fetchCar() {
        hydrateCar()
        const s = carShared.value
        if (!showCar || !s.tokens || s.revoked || !carClientId)
            return
        if (s.fetching && Date.now() - s.fetching < 60000)
            return
        const done = patch => setCar(Object.assign({ fetching: 0, nextAt: Date.now() + 5 * 60000 }, patch))
        setCar({ fetching: Date.now(), key: carKey })

        const run = (tokens, retried) => {
            const headers = { "Authorization": "Bearer " + tokens.access_token }
            const get = (path, cb) => request("GET", dataApiUrl + path, headers, null, (status, text) => {
                let json = null
                try {
                    json = JSON.parse(text)
                } catch (e) {}
                cb(status === 200 ? json : null, status)
            })

            get("/v1/homes", (homes, status) => {
                if (status === 401 && !retried)
                    return refreshCarTokens(t => t ? run(t, true) : done({}))
                if (!homes || !homes.homes || !homes.homes.length)
                    return done({ data: null, found: [], fetched: true, error: status === 200 ? "" : httpError(status) })
                const base = "/v1/homes/" + homes.homes[0].id + "/devices"
                get(base, (list, status2) => {
                    if (!list || !list.devices)
                        return done({ data: null, found: [], fetched: true, error: httpError(status2) })
                    const ids = list.devices.filter(d => d.info.brand !== "Tibber").map(d => d.id)
                    const bodies = []
                    const next = i => {
                        if (i === ids.length) {
                            const picked = Tibber.pickCar(bodies, carName)
                            return done({ data: picked.car, found: picked.found, fetched: true, error: "" })
                        }
                        get(base + "/" + ids[i], d => {
                            if (d)
                                bodies.push(d)
                            next(i + 1)
                        })
                    }
                    next(0)
                })
            })
        }

        if (Tibber.needsRefresh(s.tokens, Date.now()))
            refreshCarTokens(t => t ? run(t, false) : done({}))
        else
            run(s.tokens, false)
    }

    readonly property string carKey: showCar + "|" + carClientId + "|" + carName
    // Only a key different from the one the last fetch used needs a new fetch; startup loading must not cause one.
    onCarKeyChanged: {
        if (carShared.value.key !== carKey)
            setCar({ nextAt: 0 })
        keyDebounce.restart()
    }

    function refreshIfDue() {
        now = Date.now()
        if (now >= st.nextAt)
            refresh()
        if (showCar) {
            secretView.reload()
            if (now >= car.nextAt)
                fetchCar()
        }
    }

    // Changing where prices come from should not wait for the next interval.
    // The delay lets FileView load a changed token path before it is read.
    readonly property string fetchKey: tokenFile + "|" + homeId + "|" + priceArea
    onFetchKeyChanged: {
        if (shared.value.key !== fetchKey)
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
                text: root.priceNumber
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.unitText !== ""
                text: root.unitText
                font.pixelSize: root.textSize - 2
                color: Theme.surfaceVariantText
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
