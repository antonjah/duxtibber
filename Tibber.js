.pragma library

// Public Tibber demo token (developer.tibber.com explorer); data is auto-generated.
var DEMO_TOKEN = "3A77EECF61BD445F47241A5A36202185C35AF3AF58609E19B53F3A8872AD7BE1-1"
var API_URL = "https://api.tibber.com/v1-beta/gql"

var PRICE = "total energy tax startsAt level currency"
var QUERY = "query { viewer { homes { id appNickname timeZone currentSubscription {"
    + " priceInfo(resolution: QUARTER_HOURLY) { today { " + PRICE + " } tomorrow { " + PRICE + " } } }"
    + " consumption(resolution: HOURLY, last: 24) { nodes { from to consumption cost currency } } } } }"

function slot(p, day) {
    return { t: Date.parse(p.startsAt), total: p.total, energy: p.energy, tax: p.tax, level: p.level, day: day }
}

// Turns a GraphQL response body into a flat model, or { error } with a user-facing reason.
function parse(body, homeId) {
    var json
    try {
        json = typeof body === "string" ? JSON.parse(body) : body
    } catch (e) {
        return { error: "Bad response" }
    }
    if (json.errors && json.errors.length)
        return { error: json.errors[0].message }

    var homes = (json.data && json.data.viewer && json.data.viewer.homes) || []
    var home = homes.filter(function (h) { return homeId ? h.id === homeId : h.currentSubscription })[0]
    if (!home || !home.currentSubscription || !home.currentSubscription.priceInfo)
        return { error: "No home with a subscription" }

    var info = home.currentSubscription.priceInfo
    var prices = (info.today || []).map(function (p) { return slot(p, "today") })
        .concat((info.tomorrow || []).map(function (p) { return slot(p, "tomorrow") }))
        .sort(function (a, b) { return a.t - b.t })
    if (!prices.length)
        return { error: "No prices" }

    var cons = ((home.consumption && home.consumption.nodes) || []).filter(function (n) { return n.consumption !== null })
    return {
        home: { id: home.id, name: home.appNickname || home.id },
        currency: (info.today[0] || info.tomorrow[0]).currency,
        prices: prices,
        tomorrowReady: !!(info.tomorrow && info.tomorrow.length),
        consumption: {
            kwh: cons.reduce(function (s, n) { return s + n.consumption }, 0),
            cost: cons.reduce(function (s, n) { return s + (n.cost || 0) }, 0),
            hours: cons.length
        }
    }
}

// Slot length is inferred from the data so hourly and quarter-hourly both work.
function slotMs(prices) {
    return prices.length > 1 ? prices[1].t - prices[0].t : 3600000
}

function current(prices, now) {
    var len = slotMs(prices)
    for (var i = 0; i < prices.length; i++)
        if (prices[i].t <= now && now < prices[i].t + len)
            return prices[i]
    return null
}

function stats(prices, now) {
    var today = prices.filter(function (p) { return p.day === "today" })
    var upcoming = prices.filter(function (p) { return p.t + slotMs(prices) > now })
    var min = function (a) { return a.reduce(function (m, p) { return p.total < m.total ? p : m }) }
    var max = function (a) { return a.reduce(function (m, p) { return p.total > m.total ? p : m }) }
    return {
        min: today.length ? min(today) : null,
        max: today.length ? max(today) : null,
        avg: today.length ? today.reduce(function (s, p) { return s + p.total }, 0) / today.length : 0,
        cheapestUpcoming: upcoming.length ? min(upcoming) : null
    }
}

var MINOR = { SEK: "öre", NOK: "øre", EUR: "ct" }

function fmtPrice(total, minor) {
    return minor ? String(Math.round(total * 100)) : total.toFixed(2)
}

function unitShort(currency, minor) {
    return minor ? MINOR[currency] || currency : currency
}

function unit(currency, minor) {
    return unitShort(currency, minor) + "/kWh"
}

// Price areas without a token: the country picks the free spot-price API and the currency.
var AREAS = {
    SE1: { country: "SE", currency: "SEK" },
    SE2: { country: "SE", currency: "SEK" },
    SE3: { country: "SE", currency: "SEK" },
    SE4: { country: "SE", currency: "SEK" },
    NO1: { country: "NO", currency: "NOK" },
    NO2: { country: "NO", currency: "NOK" },
    NO3: { country: "NO", currency: "NOK" },
    NO4: { country: "NO", currency: "NOK" },
    NO5: { country: "NO", currency: "NOK" }
}
var SPOT_HOST = { SE: "https://www.elprisetjustnu.se", NO: "https://www.hvakosterstrommen.no" }

function pad(n) {
    return n < 10 ? "0" + n : "" + n
}

// base overrides the host so tests can point at a mock server.
function spotUrl(area, date, base) {
    var a = AREAS[area]
    if (!a)
        return ""
    return (base || SPOT_HOST[a.country]) + "/api/v1/prices/" + date.getFullYear() + "/"
        + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + "_" + area + ".json"
}

// Tibber's own definition: price relative to the average (<=60% very cheap ... >=140% very expensive).
function levelOf(total, avg) {
    if (avg <= 0)
        return "NORMAL"
    var r = total / avg
    return r <= 0.6 ? "VERY_CHEAP" : r <= 0.9 ? "CHEAP" : r < 1.15 ? "NORMAL" : r < 1.4 ? "EXPENSIVE" : "VERY_EXPENSIVE"
}

// Same model as parse(), from the spot-price JSON for today and (when published) tomorrow.
function parseSpot(area, todayBody, tomorrowBody) {
    var a = AREAS[area]
    if (!a)
        return { error: "Unknown price area" }
    var key = a.currency + "_per_kWh"
    var conv = function (body, day) {
        var list
        try {
            list = typeof body === "string" ? JSON.parse(body) : body
        } catch (e) {
            list = null
        }
        return (list || []).map(function (p) {
            return { t: Date.parse(p.time_start), total: p[key], energy: p[key], tax: 0, level: "", day: day }
        })
    }
    var today = conv(todayBody, "today")
    var tomorrow = tomorrowBody ? conv(tomorrowBody, "tomorrow") : []
    var prices = today.concat(tomorrow).sort(function (x, y) { return x.t - y.t })
    if (!prices.length)
        return { error: "No prices" }
    var avg = prices.reduce(function (s, p) { return s + p.total }, 0) / prices.length
    prices.forEach(function (p) { p.level = levelOf(p.total, avg) })
    return {
        home: { id: area, name: area },
        currency: a.currency,
        prices: prices,
        tomorrowReady: tomorrow.length > 0,
        consumption: { kwh: 0, cost: 0, hours: 0 },
        spot: true
    }
}

// Y gridlines at 1/2/5 x 10^n in the displayed unit, covering lo..hi; v is in major units.
// The first and last tick are the chart bounds.
function yTicks(lo, hi, minor) {
    var k = minor ? 100 : 1
    var a = lo * k, b = hi * k
    var raw = (b - a) / 4
    var mag = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10))
    var f = raw / mag
    var best = [1, 2, 5, 10].reduce(function (m, c) {
        return Math.abs(Math.log(f / c)) < Math.abs(Math.log(f / m)) ? c : m
    })
    var step = best * mag
    var dec = step >= 1 ? 0 : step >= 0.1 ? 1 : 2
    var out = []
    for (var i = Math.floor(a / step + 1e-9); i <= Math.ceil(b / step - 1e-9); i++)
        out.push({ v: (i * step + 0) / k, label: (i * step + 0).toFixed(dec) })
    return out
}

// Axis labels every 6 h on the hour, as slot index plus two-digit hour.
function ticks(prices) {
    var out = []
    prices.forEach(function (p, i) {
        var d = new Date(p.t)
        if (d.getMinutes() === 0 && d.getHours() % 6 === 0)
            out.push({ i: i, label: pad(d.getHours()) })
    })
    return out
}

// Maps Tibber's price level to a Theme color name.
function levelColor(level) {
    switch (level) {
    case "VERY_CHEAP":
    case "CHEAP":
        return "success"
    case "EXPENSIVE":
        return "warning"
    case "VERY_EXPENSIVE":
        return "error"
    default:
        return "surfaceText"
    }
}

// Retries a failed fetch after a minute so a not-yet-up network does not wait a full interval.
function nextFetch(now, ok, minutes) {
    return now + (ok ? minutes * 60000 : 60000)
}

// Chart bounds; negative prices (common on Nordic markets) extend the range below zero.
function range(prices) {
    var lo = 0, hi = 0
    prices.forEach(function (p) {
        lo = Math.min(lo, p.total)
        hi = Math.max(hi, p.total)
    })
    return { lo: lo, hi: hi > lo ? hi : lo + 1 }
}
