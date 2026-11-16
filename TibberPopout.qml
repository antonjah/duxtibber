import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "Tibber.js" as Tibber

PopoutComponent {
    id: popout

    required property var plugin

    readonly property var st: plugin.st
    readonly property var cur: plugin.cur
    readonly property var model: st.model
    readonly property var stats: model ? Tibber.stats(model.prices, plugin.now) : null
    readonly property var yTicks: model ? Tibber.yTicks(Tibber.range(model.prices).lo, Tibber.range(model.prices).hi, plugin.minor) : []
    readonly property string unit: model ? Tibber.unit(model.currency, plugin.minor) : ""
    readonly property int deltaPct: cur && model && model.baseline > 0 ? Math.round((cur.total / model.baseline - 1) * 100) : 0

    headerText: I18n.trFor("duxTibber", "Electricity price")
    detailsText: model
        ? model.home.name + (model.spot ? " · " + I18n.trFor("duxTibber", "Spot price, excl. fees and tax") : "") + (st.demo ? " · " + I18n.trFor("duxTibber", "Demo data") : "")
        : ""
    showCloseButton: true

    function fmt(v) {
        return Tibber.fmtPrice(v, plugin.minor)
    }

    function fmtU(v) {
        return fmt(v) + (plugin.showUnit ? " " + Tibber.unitShort(model.currency, plugin.minor) : "")
    }

    function hhmm(ms) {
        return Qt.formatTime(new Date(ms), "HH:mm")
    }

    function span(p) {
        return hhmm(p.t) + "–" + hhmm(p.t + Tibber.slotMs(model.prices))
    }

    function when(p) {
        return (p.day === "tomorrow" ? I18n.trFor("duxTibber", "tomorrow") + " " : "") + hhmm(p.t)
    }

    function levelLabel(level) {
        switch (level) {
        case "VERY_CHEAP": return I18n.trFor("duxTibber", "Very cheap")
        case "CHEAP": return I18n.trFor("duxTibber", "Cheap")
        case "EXPENSIVE": return I18n.trFor("duxTibber", "Expensive")
        case "VERY_EXPENSIVE": return I18n.trFor("duxTibber", "Very expensive")
        default: return I18n.trFor("duxTibber", "Normal")
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            visible: !popout.model && !popout.st.error
            width: parent.width
            text: I18n.trFor("duxTibber", "Loading…")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }

        Rectangle {
            visible: popout.st.error !== ""
            width: parent.width
            height: errorRow.height + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Qt.alpha(Theme.error, 0.14)

            Row {
                id: errorRow
                x: Theme.spacingM
                y: Theme.spacingM
                width: parent.width - Theme.spacingM * 2
                spacing: Theme.spacingS

                DIcon {
                    name: "error"
                    size: Theme.iconSize
                    color: Theme.error
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: popout.st.error + (popout.model ? " · " + I18n.trFor("duxTibber", "showing last data") : "")
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeMedium
                    wrapMode: Text.WordWrap
                    width: parent.width - Theme.iconSize - Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Rectangle {
            visible: !!popout.cur
            width: parent.width
            height: hero.height + Theme.spacingL * 2
            radius: Theme.cornerRadius * 1.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(popout.plugin.levelColor, 0.18) }
                GradientStop { position: 0.75; color: Theme.surfaceContainerHigh }
            }

            Column {
                id: hero
                x: Theme.spacingL
                y: Theme.spacingL
                width: parent.width - Theme.spacingL * 2
                spacing: Theme.spacingXS

                Item {
                    width: parent.width
                    height: levelChip.height

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: popout.cur ? I18n.trFor("duxTibber", "Right now · %1").arg(popout.span(popout.cur)) : ""
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Rectangle {
                        id: levelChip
                        anchors.right: parent.right
                        width: levelText.width + Theme.spacingM * 2
                        height: levelText.height + Theme.spacingXS * 2
                        radius: height / 2
                        color: Qt.alpha(popout.plugin.levelColor, 0.2)

                        StyledText {
                            id: levelText
                            anchors.centerIn: parent
                            text: popout.cur ? popout.levelLabel(popout.cur.level) : ""
                            color: popout.plugin.levelColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: heroPrice.height

                    StyledText {
                        id: heroPrice
                        text: popout.cur ? popout.fmt(popout.cur.total) : ""
                        color: popout.plugin.levelColor
                        font.pixelSize: Theme.fontSizeXLarge * 2
                        font.weight: Font.Bold
                    }

                    StyledText {
                        anchors.left: heroPrice.right
                        anchors.leftMargin: Theme.spacingS
                        anchors.baseline: heroPrice.baseline
                        text: popout.unit
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }

                Row {
                    visible: !!popout.model && popout.model.baseline > 0
                    spacing: Theme.spacingXS

                    DIcon {
                        name: popout.deltaPct >= 0 ? "arrow_upward" : "arrow_downward"
                        size: Theme.fontSizeMedium
                        color: popout.plugin.levelColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: (popout.deltaPct >= 0
                            ? I18n.trFor("duxTibber", "%1% above the 3-day average")
                            : I18n.trFor("duxTibber", "%1% below the 3-day average")).arg(Math.abs(popout.deltaPct))
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                StyledText {
                    visible: !!popout.cur && !popout.model.spot
                    text: popout.cur
                        ? I18n.trFor("duxTibber", "Energy %1 · Tax %2").arg(popout.fmtU(popout.cur.energy)).arg(popout.fmtU(popout.cur.tax))
                        : ""
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        Rectangle {
            visible: !!popout.model
            width: parent.width
            height: chartBody.height + Theme.spacingM * 2
            radius: Theme.cornerRadius * 1.5
            color: Theme.surfaceContainerHigh

            Column {
                id: chartBody
                x: Theme.spacingM
                y: Theme.spacingM
                width: parent.width - Theme.spacingM * 2
                spacing: Theme.spacingS

                Item {
                    width: parent.width
                    height: unitText.height

                    StyledText {
                        id: unitText
                        text: popout.unit
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    StyledText {
                        anchors.right: parent.right
                        visible: !!popout.model && !popout.model.tomorrowReady
                        text: I18n.trFor("duxTibber", "Tomorrow's prices arrive around 13:00")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                PriceChart {
                    width: parent.width
                    height: 180
                    prices: popout.model ? popout.model.prices : []
                    cur: popout.cur
                    now: popout.plugin.now
                    avg: popout.model && popout.model.baseline > 0 ? popout.model.baseline : (popout.stats ? popout.stats.avg : 0)
                    yTicks: popout.yTicks
                    xTicks: popout.model ? Tibber.ticks(popout.model.prices) : []
                    tomorrowLabel: I18n.trFor("duxTibber", "Tomorrow")
                    levelColor: popout.plugin.levelColor
                }
            }
        }

        Row {
            id: statsRow
            visible: !!popout.stats && !!popout.stats.min
            width: parent.width
            spacing: Theme.spacingS

            StatTile {
                width: (statsRow.width - Theme.spacingS * 2) / 3
                label: I18n.trFor("duxTibber", "Lowest")
                icon: "trending_down"
                accent: Theme.success
                value: popout.stats && popout.stats.min ? popout.fmtU(popout.stats.min.total) : ""
                sub: popout.stats && popout.stats.min ? popout.span(popout.stats.min) : ""
            }

            StatTile {
                width: (statsRow.width - Theme.spacingS * 2) / 3
                label: I18n.trFor("duxTibber", "Average")
                icon: "show_chart"
                accent: Theme.primary
                value: popout.stats ? popout.fmtU(popout.stats.avg) : ""
                sub: I18n.trFor("duxTibber", "Today")
            }

            StatTile {
                width: (statsRow.width - Theme.spacingS * 2) / 3
                label: I18n.trFor("duxTibber", "Highest")
                icon: "trending_up"
                accent: Theme.error
                value: popout.stats && popout.stats.max ? popout.fmtU(popout.stats.max.total) : ""
                sub: popout.stats && popout.stats.max ? popout.span(popout.stats.max) : ""
            }
        }

        Row {
            id: extraRow
            readonly property bool hasUsage: !!popout.model && popout.model.consumption.hours > 0
            visible: !!popout.stats && !!popout.stats.cheapestUpcoming
            width: parent.width
            spacing: Theme.spacingS

            StatTile {
                width: extraRow.hasUsage ? (extraRow.width - Theme.spacingS) / 2 : extraRow.width
                label: I18n.trFor("duxTibber", "Cheapest ahead")
                icon: "schedule"
                accent: Theme.success
                value: popout.stats && popout.stats.cheapestUpcoming ? popout.fmtU(popout.stats.cheapestUpcoming.total) : ""
                sub: popout.stats && popout.stats.cheapestUpcoming ? popout.when(popout.stats.cheapestUpcoming) : ""
            }

            StatTile {
                visible: extraRow.hasUsage
                width: (extraRow.width - Theme.spacingS) / 2
                label: extraRow.hasUsage ? I18n.trFor("duxTibber", "Last %1 h").arg(popout.model.consumption.hours) : ""
                icon: "electric_meter"
                accent: Theme.primary
                value: extraRow.hasUsage ? popout.model.consumption.kwh.toFixed(1) + " kWh" : ""
                sub: extraRow.hasUsage ? popout.model.consumption.cost.toFixed(0) + " " + popout.model.currency : ""
            }
        }

        StyledText {
            visible: popout.st.updatedAt > 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: I18n.trFor("duxTibber", "Updated %1 · right-click the bar widget to refresh").arg(popout.hhmm(popout.st.updatedAt))
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
