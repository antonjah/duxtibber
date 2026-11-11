import QtQuick
import qs.Common

// Stepped price line over a gradient area, with labelled gridlines and a marker for the current time.
Canvas {
    id: chart

    property var prices: []
    property var cur: null
    property real now: 0
    property real avg: 0
    property var yTicks: []
    property var xTicks: []
    property string tomorrowLabel: ""
    property color levelColor: Theme.surfaceText

    readonly property real padL: 34
    readonly property real padB: 20

    onPricesChanged: requestPaint()
    onNowChanged: requestPaint()
    onYTicksChanged: requestPaint()
    onLevelColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const n = prices.length
        if (n === 0 || yTicks.length < 2)
            return

        const lo = yTicks[0].v
        const hi = yTicks[yTicks.length - 1].v
        const x0 = padL
        const x1 = width - 2
        const y0 = 10
        const y1 = height - padB
        const sw = (x1 - x0) / n
        const slot = n > 1 ? prices[1].t - prices[0].t : 3600000
        const yOf = v => y0 + (hi - v) / (hi - lo) * (y1 - y0)
        const label = Theme.fontSizeSmall + "px \"" + Theme.fontFamily + "\""

        ctx.font = label
        ctx.textBaseline = "middle"
        for (const t of yTicks) {
            const y = Math.round(yOf(t.v)) + 0.5
            ctx.strokeStyle = Qt.alpha(Theme.surfaceText, t.v === 0 && lo < 0 ? 0.3 : 0.08)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(x0, y)
            ctx.lineTo(x1, y)
            ctx.stroke()
            ctx.fillStyle = Theme.surfaceVariantText
            ctx.textAlign = "right"
            ctx.fillText(t.label, x0 - 8, y)
        }

        // Colour follows the level thresholds around the average, so expensive peaks glow warm.
        const pos = v => Math.min(0.97, Math.max(0, (yOf(v) - y0) / (y1 - y0)))
        const stops = [
            [pos(Math.max(hi, avg * 1.4)), Theme.error],
            [pos(avg * 1.15), Theme.warning],
            [pos(avg * 0.9), Theme.success]
        ]

        const step = () => {
            ctx.moveTo(x0, yOf(prices[0].total))
            for (let i = 0; i < n; i++) {
                ctx.lineTo(x0 + i * sw, yOf(prices[i].total))
                ctx.lineTo(x0 + (i + 1) * sw, yOf(prices[i].total))
            }
        }

        const area = ctx.createLinearGradient(0, y0, 0, y1)
        stops.forEach((s, i) => area.addColorStop(s[0], Qt.alpha(s[1], 0.34 - i * 0.06)))
        area.addColorStop(1, Qt.alpha(Theme.success, 0.02))
        ctx.beginPath()
        step()
        ctx.lineTo(x1, yOf(Math.max(lo, 0)))
        ctx.lineTo(x0, yOf(Math.max(lo, 0)))
        ctx.closePath()
        ctx.fillStyle = area
        ctx.fill()

        const line = ctx.createLinearGradient(0, y0, 0, y1)
        stops.forEach(s => line.addColorStop(s[0], s[1]))
        ctx.beginPath()
        step()
        ctx.strokeStyle = line
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.stroke()

        const xNow = Math.min(x1, Math.max(x0, x0 + (now - prices[0].t) / slot * sw))
        ctx.fillStyle = Qt.alpha(Theme.surfaceContainerHigh, 0.55)
        ctx.fillRect(x0, y0, xNow - x0, y1 - y0)

        const next = prices.findIndex((p, i) => i > 0 && p.day === "tomorrow" && prices[i - 1].day === "today")
        if (next > 0) {
            const xd = Math.round(x0 + next * sw) + 0.5
            ctx.setLineDash([3, 3])
            ctx.strokeStyle = Qt.alpha(Theme.surfaceText, 0.3)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(xd, y0)
            ctx.lineTo(xd, y1)
            ctx.stroke()
            ctx.setLineDash([])
            ctx.fillStyle = Theme.surfaceVariantText
            ctx.textAlign = "left"
            ctx.textBaseline = "top"
            ctx.fillText(tomorrowLabel, xd + 6, y0 + 2)
        }

        ctx.fillStyle = Theme.surfaceVariantText
        ctx.textAlign = "center"
        ctx.textBaseline = "top"
        for (const t of xTicks)
            ctx.fillText(t.label, x0 + t.i * sw, y1 + 6)

        if (cur) {
            const yNow = yOf(cur.total)
            ctx.strokeStyle = Qt.alpha(levelColor, 0.35)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(xNow, yNow)
            ctx.lineTo(xNow, y1)
            ctx.stroke()
            ctx.fillStyle = Qt.alpha(levelColor, 0.25)
            ctx.beginPath()
            ctx.arc(xNow, yNow, 9, 0, 2 * Math.PI)
            ctx.fill()
            ctx.fillStyle = levelColor
            ctx.strokeStyle = Theme.surfaceContainerHigh
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.arc(xNow, yNow, 5, 0, 2 * Math.PI)
            ctx.fill()
            ctx.stroke()
        }
    }
}
