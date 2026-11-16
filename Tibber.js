.pragma library

// Public Tibber demo token (developer.tibber.com explorer); data is auto-generated.
var DEMO_TOKEN = "3A77EECF61BD445F47241A5A36202185C35AF3AF58609E19B53F3A8872AD7BE1-1"
var API_URL = "https://api.tibber.com/v1-beta/gql"

var PRICE = "total energy tax startsAt level currency"
var QUERY = "query { viewer { homes { id appNickname timeZone currentSubscription {"
    + " priceInfo(resolution: QUARTER_HOURLY) { today { " + PRICE + " } tomorrow { " + PRICE + " } }"
    + " priceInfoRange(resolution: HOURLY, last: 72) { nodes { total } } }"
    + " consumption(resolution: HOURLY, last: 24) { nodes { from to consumption cost currency } } } } }"

var WINDOW_MS = 72 * 3600000

function mean(list) {
    return list.length ? list.reduce(function (s, v) { return s + v }, 0) / list.length : 0
}

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
    var range = (home.currentSubscription.priceInfoRange && home.currentSubscription.priceInfoRange.nodes) || []
    return {
        home: { id: home.id, name: home.appNickname || home.id },
        currency: (info.today[0] || info.tomorrow[0]).currency,
        prices: prices,
        baseline: mean(range.map(function (n) { return n.total })),
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

// Tibber's own definition: price relative to the trailing 3-day average (<=60% very cheap ... >=140% very expensive).
function levelOf(total, baseline) {
    if (baseline <= 0)
        return "NORMAL"
    var r = total / baseline
    return r <= 0.6 ? "VERY_CHEAP" : r <= 0.9 ? "CHEAP" : r < 1.15 ? "NORMAL" : r < 1.4 ? "EXPENSIVE" : "VERY_EXPENSIVE"
}

// Same model as parse(), from spot-price JSON: pastBodies are the previous days, tomorrowBody is optional.
function parseSpot(area, todayBody, tomorrowBody, pastBodies, now) {
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
    var past = []
    ;(pastBodies || []).forEach(function (b) { past = past.concat(conv(b, "past")) })
    var t0 = now === undefined ? Date.now() : now
    var window = past.concat(today).filter(function (p) { return p.t >= t0 - WINDOW_MS && p.t < t0 })
    // Without history (first day, API down) the best available baseline is today's own average.
    var baseline = mean((window.length ? window : today).map(function (p) { return p.total }))
    var prices = today.concat(tomorrow).sort(function (x, y) { return x.t - y.t })
    if (!prices.length)
        return { error: "No prices" }
    prices.forEach(function (p) { p.level = levelOf(p.total, baseline) })
    return {
        home: { id: area, name: area },
        currency: a.currency,
        prices: prices,
        baseline: baseline,
        tomorrowReady: tomorrow.length > 0,
        consumption: { kwh: 0, cost: 0, hours: 0 },
        spot: true
    }
}

function capability(device, id) {
    var c = (device.capabilities || []).filter(function (x) { return x.id === id })[0]
    return c ? c.value : undefined
}

function attribute(device, id) {
    var a = (device.attributes || []).filter(function (x) { return x.id === id })[0]
    return a ? a.value : undefined
}

// Connected cars among the Data API device detail bodies; the Tibber "Dummy" device is ignored.
function cars(bodies) {
    return bodies.map(function (b) { return typeof b === "string" ? JSON.parse(b) : b })
        .filter(function (x) {
            return x.info && x.info.brand !== "Tibber" && capability(x, "storage.stateOfCharge") !== undefined
        })
        .map(function (d) {
            var plug = capability(d, "connector.status")
            return {
                id: d.id,
                brand: d.info.brand,
                model: d.info.model,
                name: d.info.name || d.info.model,
                soc: capability(d, "storage.stateOfCharge"),
                target: capability(d, "storage.targetStateOfCharge"),
                rangeKm: Math.round((capability(d, "range.remaining") || 0) / 1000),
                plugged: plug !== undefined && plug !== "disconnected" && plug !== "unknown",
                charging: capability(d, "charging.status") === "charging",
                online: attribute(d, "isOnline") !== false,
                lastSeen: d.status && d.status.lastSeen ? Date.parse(d.status.lastSeen) : 0
            }
        })
}

// One car: matched by name, model or id (case-insensitive), else the first. found lists every car's name.
function pickCar(bodies, name) {
    var all = cars(bodies)
    var want = (name || "").trim().toLowerCase()
    var hit = want
        ? all.filter(function (c) {
            return [c.name, c.model, c.id].some(function (v) { return String(v || "").toLowerCase() === want })
        })[0]
        : all[0]
    return { car: hit || null, found: all.map(function (c) { return c.name }) }
}

var AUTH_HOST = "https://thewall.tibber.com"
var DATA_HOST = "https://data-api.tibber.com"
var CLIENTS_URL = "https://data-api.tibber.com/clients/manage"
var CAR_REDIRECT = "http://localhost:8765/callback"
// The login is pasted in by hand, so nothing can inject a code; the state only proves the address came from our link.
var CAR_STATE = "duxtibber"
var CAR_SCOPES = "openid profile email offline_access data-api-user-read data-api-homes-read data-api-vehicles-read"

function formEncode(obj) {
    return Object.keys(obj).map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(obj[k]) }).join("&")
}

function authUrl(clientId, state, base) {
    return (base || AUTH_HOST) + "/connect/authorize?"
        + formEncode({ response_type: "code", client_id: clientId, redirect_uri: CAR_REDIRECT, scope: CAR_SCOPES, state: state })
}

// The address the browser ends up on after approving; state must be the one the login was started with.
function parseRedirect(text, state) {
    var q = String(text || "").trim()
    var i = q.indexOf("?")
    if (i < 0)
        return { error: "Paste the whole address from the browser" }
    var args = {}
    try {
        q.slice(i + 1).split("#")[0].split("&").forEach(function (kv) {
            var j = kv.indexOf("=")
            if (j > 0)
                args[decodeURIComponent(kv.slice(0, j))] = decodeURIComponent(kv.slice(j + 1).replace(/\+/g, " "))
        })
    } catch (e) {
        return { error: "Could not read the address" }
    }
    if (args.error)
        return { error: args.error_description || OAUTH_ERRORS[args.error] || args.error }
    if (!args.code)
        return { error: "The address has no login code" }
    if (!state || args.state !== state)
        return { error: "This login was started elsewhere; click Connect again" }
    return { code: args.code }
}

function tokenBody(clientId, secret, grant) {
    var b = { client_id: clientId, client_secret: secret }
    if (grant.code) {
        b.grant_type = "authorization_code"
        b.code = grant.code
        b.redirect_uri = CAR_REDIRECT
    } else {
        b.grant_type = "refresh_token"
        b.refresh_token = grant.refresh
    }
    return formEncode(b)
}

var OAUTH_ERRORS = {
    invalid_grant: "Tibber rejected the login. The code works once and expires quickly: click Open Tibber login and try again",
    invalid_client: "Tibber did not accept the client ID or secret. Check both in the plugin settings",
    access_denied: "The login was cancelled"
}

// Token endpoint response -> stored tokens; a refresh may omit the refresh token, so the previous one is kept.
function tokensFrom(body, now, previous) {
    var j
    try {
        j = typeof body === "string" ? JSON.parse(body) : body
    } catch (e) {
        return { error: "Bad response" }
    }
    if (!j || !j.access_token)
        return { error: (j && (j.error_description || OAUTH_ERRORS[j.error] || j.error)) || "Bad response", revoked: !!(j && j.error === "invalid_grant") }
    return {
        access_token: j.access_token,
        refresh_token: j.refresh_token || (previous && previous.refresh_token) || "",
        expires_at: now + (j.expires_in || 3600) * 1000
    }
}

function needsRefresh(tokens, now) {
    return !tokens || !tokens.access_token || tokens.expires_at - now < 300000
}

// What the car tile shows; c = { enabled, clientId, hasSecret, tokens, revoked, car, found, name, error, fetched }.
function carStatus(c) {
    if (!c.enabled)
        return "off"
    if (!c.clientId || !c.hasSecret)
        return "setup"
    if (c.revoked)
        return "reconnect"
    if (!c.tokens || !c.tokens.refresh_token)
        return "connect"
    if (c.car)
        return "car"
    if (c.error)
        return "error"
    if (!c.fetched)
        return "loading"
    return c.name && c.found && c.found.length ? "notfound" : "nocar"
}

// Calendar days between t and now in local time (0 = today).
function daysAgo(t, now) {
    var a = new Date(t), b = new Date(now)
    return Math.round((new Date(b.getFullYear(), b.getMonth(), b.getDate()) - new Date(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000)
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
