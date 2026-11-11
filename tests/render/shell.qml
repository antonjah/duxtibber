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
    readonly property var scenes: [
        { name: "demo", token: "none" },
        { name: "token", token: "good", vertical: true },
        { name: "negative", token: "negative" },
        { name: "stale", token: "good", swap: "expired" },
        { name: "error", token: "expired" },
        { name: "twoscreens", token: "good", twin: true },
        { name: "spot", token: "none", area: "SE3", minor: true },
        { name: "spotno", token: "none", area: "NO1" },
        { name: "declared", token: "none", declared: { priceArea: "SE3", priceUnit: "minor", refreshMinutes: 30 } }
    ]
    property int sceneIndex: -1

    // The plugin reads this declared-settings file; each scene rewrites it.
    FileView {
        id: declaredFile
        path: Quickshell.env("XDG_CONFIG_HOME") + "/tibber/config.json"
        blockWrites: true
        printErrors: false
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
        interval: 800
        onTriggered: shell.nextScene()
    }

    FloatingWindow {
        implicitWidth: 540
        implicitHeight: 920
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
        const w = c.createObject(widgetHost, { pluginService: PluginService, pluginId: pid })
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
        declaredFile.setText(JSON.stringify(scene.declared || {}))
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
        interval: 200
        repeat: true
        onTriggered: {
            tries++
            const st = shell.widgets[0].st
            const done = st.nextAt > shell.swapFrom && st.fetching === 0
            if (!done && tries < 50)
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
        interval: 400
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
        console.log("TIBBER " + scene.name + " pill=" + w.priceText + " level=" + (w.cur ? w.cur.level : "none")
            + " demo=" + w.st.demo + " error=" + JSON.stringify(w.st.error) + " model=" + (w.st.model ? w.st.model.prices.length : 0)
            + " twinSame=" + (widgets.length > 1 ? (widgets[1].st.nextAt === w.st.nextAt) : "n/a"))
        settle.start()
    }

    Timer {
        id: settle
        interval: 700
        onTriggered: stage.grabToImage(result => {
            result.saveToFile(shell.shotDir + "/" + shell.scene.name + ".png")
            shell.nextScene()
        })
    }
}
