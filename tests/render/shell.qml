// Quickshell config for tests/render.sh; do not run it directly.
// Hosts the real plugin with the real DMS components and writes one PNG per scene.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Common as DC

ShellRoot {
    id: shell

    readonly property string pluginDir: Quickshell.env("DUXTIBBER_DIR")
    readonly property string shotDir: Quickshell.env("DUXTIBBER_SHOTS")
    readonly property string tokenDir: Quickshell.env("DUXTIBBER_TOKENS")
    readonly property string apiUrl: Quickshell.env("DUXTIBBER_API")
    readonly property string pid: "duxTibber"

    // token: file under tokenDir ("none" = missing file = demo). swap: token to switch to after the first load.
    readonly property var allScenes: [
        { name: "demo", token: "none" },
        { name: "token", token: "good", vertical: true },
        { name: "negative", token: "negative" },
        { name: "stale", token: "good", swap: "expired" },
        { name: "error", token: "expired" },
        { name: "twoscreens", token: "good", twin: true },
        { name: "spot", token: "none", area: "SE3", minor: true },
        { name: "spotno", token: "none", area: "NO1" },
        { name: "declared", token: "none", declared: { priceArea: "SE3", priceUnit: "minor", refreshMinutes: 30 } },
        { name: "nounit", token: "none", area: "SE3", minor: true, nounit: true },
        { name: "car", token: "none", car: { show: true, clientId: "cid-test", tokens: { access: "carok", refresh: "r-ok", fresh: true } } },
        { name: "carOff", token: "none", car: { show: false, clientId: "cid-test", tokens: { access: "carok", refresh: "r-ok", fresh: true } } },
        { name: "carSetup", token: "none", car: { show: true } },
        { name: "carNoSecret", token: "none", car: { show: true, clientId: "cid-test", secret: false } },
        { name: "carConnect", token: "none", car: { show: true, clientId: "cid-test" } },
        { name: "carSecretLate", token: "none", car: { show: true, clientId: "cid-test", late: true } },
        { name: "carClipboard", token: "none", car: { show: true, clientId: "cid-test", clip: "http://localhost:8765/callback?code=GOODCODE&state=duxtibber&iss=https%3A%2F%2Fthewall.tibber.com" } },
        { name: "carEmptyClip", token: "none", car: { show: true, clientId: "cid-test", clip: "" } },
        { name: "carPaste", token: "none", car: { show: true, clientId: "cid-test", paste: "http://localhost:8765/callback?code=GOODCODE&state=duxtibber&iss=https%3A%2F%2Fthewall.tibber.com" } },
        { name: "carBadPaste", token: "none", car: { show: true, clientId: "cid-test", paste: "http://localhost:8765/callback?code=BADCODE&state=duxtibber" } },
        { name: "carRefresh", token: "none", car: { show: true, clientId: "cid-test", tokens: { access: "old", refresh: "r-ok", fresh: false } } },
        { name: "carRevoked", token: "none", car: { show: true, clientId: "cid-test", tokens: { access: "old", refresh: "r-revoked", fresh: false } } },
        { name: "carSelect", token: "none", car: { show: true, clientId: "cid-test", name: "family CAR", tokens: { access: "carok", refresh: "r-ok", fresh: true } } },
        { name: "carMiss", token: "none", car: { show: true, clientId: "cid-test", name: "tesla", tokens: { access: "carok", refresh: "r-ok", fresh: true } } }
    ]
    // DUXTIBBER_ONLY="a b" renders just those scenes (fast iteration).
    readonly property string only: Quickshell.env("DUXTIBBER_ONLY") || ""
    readonly property var scenes: only ? allScenes.filter(s => only.split(" ").indexOf(s.name) >= 0) : allScenes
    property int sceneIndex: -1

    // The plugin reads this declared-settings file; each scene rewrites it.
    FileView {
        id: declaredFile
        path: Quickshell.env("XDG_CONFIG_HOME") + "/tibber/config.json"
        blockWrites: true
        printErrors: false
    }

    // The plugin's private token store for the car tile; each scene rewrites it.
    FileView {
        id: carFile
        path: Quickshell.env("XDG_STATE_HOME") + "/duxtibber/car.json"
        blockWrites: true
        printErrors: false
    }

    // Simulates the user pasting the browser address into the settings.
    Timer {
        id: pasteTimer
        interval: 100
        onTriggered: {
            SettingsData.setPluginSetting(shell.pid, "carRedirect", shell.scene.car.paste)
            PluginService.pluginDataChanged(shell.pid)
        }
    }

    // The secret file that appears while the popout is already open.
    FileView {
        id: lateFile
        path: Quickshell.env("DUXTIBBER_TOKENS") + "/latesecret"
        blockWrites: true
        printErrors: false
    }

    function find(item, name) {
        if (item.objectName === name)
            return item
        for (const child of item.children) {
            const hit = find(child, name)
            if (hit)
                return hit
        }
        return null
    }

    // Late events of the car scenes: the secret file appears, or the user clicks the clipboard button.
    Timer {
        id: actTimer
        interval: 100
        onTriggered: {
            const c = shell.scene.car
            if (c.late) {
                lateFile.setText("sekret")
            } else {
                Quickshell.clipboardText = c.clip
                const button = shell.find(popoutHost, "useAddress")
                if (button)
                    button.clicked()
            }
        }
    }
    property var widgets: []
    property var scene: null
    property int tries: 0
    property var swapFrom: 0

    Component.onCompleted: {
        DC.Style.theme = Theme
        DC.Style.settings = SettingsData
        DC.I18n.backend = I18n
        DC.Paths.backend = Paths
        DC.Log.backend = Log
        DC.Host.session = SessionService
        DC.Host.cache = CacheData
        DC.Host.files = FilesService
        start.start()
    }

    Timer {
        id: start
        interval: 300
        onTriggered: shell.nextScene()
    }

    FloatingWindow {
        implicitWidth: 540
        implicitHeight: 1240
        color: Theme.surface
        visible: true

        Item {
            id: widgetHost
            width: 0
            height: 0
        }

        Column {
            id: stage
            padding: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingL

                Rectangle {
                    id: pillChip
                    width: pillHost.childrenRect.width + Theme.spacingM * 2
                    height: 34
                    radius: Theme.cornerRadius
                    color: Theme.chipSurface

                    Item {
                        id: pillHost
                        x: Theme.spacingM
                        height: parent.height
                    }
                }

                Rectangle {
                    id: verticalChip
                    width: 40
                    height: verticalHost.childrenRect.height + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.chipSurface
                    visible: !!(shell.scene && shell.scene.vertical)

                    Item {
                        id: verticalHost
                        y: Theme.spacingM
                        width: parent.width
                    }
                }
            }

            Rectangle {
                id: popoutHost
                width: 460
                height: childrenRect.height + PopoutMetrics.contentPadding * 2
                radius: Theme.cornerRadius * 1.5
                color: Theme.surfaceContainer
                border.color: Theme.outlineVariant
                border.width: 1
            }
        }
    }

    function clearScene() {
        widgets.forEach(w => w.destroy())
        widgets = []
        for (const host of [pillHost, verticalHost, popoutHost])
            for (let i = host.children.length - 1; i >= 0; i--)
                host.children[i].destroy()
    }

    function spawn() {
        const c = Qt.createComponent("file://" + pluginDir + "/DuxTibber.qml")
        if (c.status === Component.Error) {
            console.log("TIBBER ERROR " + c.errorString())
            return null
        }
        const w = c.createObject(widgetHost, { pluginService: PluginService, pluginId: pid, recheckMs: 100 })
        widgets.push(w)
        return w
    }

    function nextScene() {
        clearScene()
        sceneIndex++
        if (sceneIndex >= scenes.length) {
            console.log("TIBBER done")
            Qt.callLater(Qt.quit)
            return
        }
        scene = scenes[sceneIndex]
        PluginService.globalVars = ({})
        SettingsData.setPluginSetting(pid, "apiUrl", apiUrl)
        SettingsData.setPluginSetting(pid, "tokenFile", tokenDir + "/" + scene.token)
        SettingsData.setPluginSetting(pid, "priceArea", scene.area || "")
        SettingsData.setPluginSetting(pid, "priceUnit", scene.minor ? "minor" : "major")
        SettingsData.setPluginSetting(pid, "showUnit", !scene.nounit)
        declaredFile.setText(JSON.stringify(scene.declared || {}))
        const c = scene.car || {}
        SettingsData.setPluginSetting(pid, "showCar", !!c.show)
        SettingsData.setPluginSetting(pid, "carClientId", c.clientId || "")
        SettingsData.setPluginSetting(pid, "carName", c.name || "")
        SettingsData.setPluginSetting(pid, "carSecretFile", tokenDir + (c.late ? "/latesecret" : c.secret === false ? "/nosecret" : "/carsecret"))
        SettingsData.setPluginSetting(pid, "carRedirect", "")
        const t = c.tokens
        carFile.setText(JSON.stringify(t ? { scene: scene.name, access_token: t.access, refresh_token: t.refresh, expires_at: t.fresh ? Date.now() + 3600000 : 1 } : { scene: scene.name }))
        if (c.paste)
            pasteTimer.start()
        spawn()
        if (scene.twin)
            spawn()
        tries = 0
        swapFrom = 0
        poll.start()
    }

    // A fetch is finished once the shared state has a nextAt and nothing in flight.
    Timer {
        id: poll
        interval: 25
        repeat: true
        onTriggered: {
            tries++
            const st = shell.widgets[0].st
            const car = shell.widgets[0].car
            const c = shell.scene.car
            // Fetch scenes wait for the car request; paste scenes for the exchange (and fetch); the others have nothing to wait for.
            const carDone = !c || !c.show || (c.paste ? (car.busy === 0 && (car.data !== null || car.message !== "")) : (c.tokens ? (car.nextAt > 0 && car.fetching === 0) : true))
            const done = st.nextAt > shell.swapFrom && st.fetching === 0 && carDone
            if (!done && tries < 400)
                return
            if (shell.scene.swap && shell.swapFrom === 0) {
                shell.swapFrom = st.nextAt
                SettingsData.setPluginSetting(shell.pid, "tokenFile", shell.tokenDir + "/" + shell.scene.swap)
                PluginService.pluginDataChanged(shell.pid)
                swapTimer.start()
                shell.tries = 0
                return
            }
            stop()
            shell.build()
        }
    }

    // The settings change reaches FileView asynchronously in the real shell too.
    Timer {
        id: swapTimer
        interval: 150
        onTriggered: shell.widgets[0].refresh()
    }

    function build() {
        const w = widgets[0]
        const pill = w.horizontalBarPill.createObject(pillHost)
        pill.anchors.verticalCenter = pillHost.verticalCenter
        if (scene.vertical)
            w.verticalBarPill.createObject(verticalHost).anchors.horizontalCenter = verticalHost.horizontalCenter
        w.popoutContent.createObject(popoutHost, {
            width: popoutHost.width - PopoutMetrics.contentPadding * 2,
            x: PopoutMetrics.contentPadding,
            y: PopoutMetrics.contentPadding
        })
        const late = scene.car && (scene.car.late || scene.car.clip !== undefined)
        if (late)
            actTimer.start()
        settle.interval = late ? 800 : 250
        settle.start()
    }

    function report() {
        const w = widgets[0]
        console.log("TIBBER " + scene.name + " pill=" + w.priceText + " level=" + (w.cur ? w.cur.level : "none")
            + " demo=" + w.st.demo + " error=" + JSON.stringify(w.st.error) + " model=" + (w.st.model ? w.st.model.prices.length : 0)
            + " twinSame=" + (widgets.length > 1 ? (widgets[1].st.nextAt === w.st.nextAt) : "n/a")
            + " carstate=" + w.carState + " car=" + (w.car.data ? w.car.data.brand + " " + w.car.data.name + "/" + w.car.data.soc + "/" + w.car.data.target + "/" + w.car.data.rangeKm : "none")
            + " tok=" + (w.car.tokens ? w.car.tokens.refresh_token : "none") + " redirect=" + (w.carRedirect === "" ? "cleared" : "set") + " msg=" + (w.car.message || "-"))
    }

    Timer {
        id: settle
        interval: 250
        onTriggered: {
            shell.report()
            stage.grabToImage(result => {
                result.saveToFile(shell.shotDir + "/" + shell.scene.name + ".png")
                shell.nextScene()
            })
        }
    }
}
