import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { loadScript } from "./qml-script.mjs";

const T = loadScript(new URL("../Tibber.js", import.meta.url));
const demo = JSON.parse(readFileSync(new URL("./fixtures/demo.json", import.meta.url), "utf8"));
const clone = (o) => JSON.parse(JSON.stringify(o));
const NOW = Date.parse("2026-11-11T12:50:00+01:00");

// A copy of the demo response where tomorrow mirrors today, shifted one day.
function withTomorrow() {
    const r = clone(demo);
    const info = r.data.viewer.homes[0].currentSubscription.priceInfo;
    info.tomorrow = info.today.map((p) => ({ ...p, startsAt: p.startsAt.replace("2026-11-11", "2026-11-12") }));
    return r;
}

test("parse flattens today and tomorrow, sorted by time", () => {
    const m = T.parse(withTomorrow());
    assert.equal(m.prices.length, 192);
    assert.equal(m.tomorrowReady, true);
    assert.ok(m.prices.every((p, i) => i === 0 || p.t > m.prices[i - 1].t));
    assert.equal(m.prices[0].day, "today");
    assert.equal(m.prices[191].day, "tomorrow");
});

test("parse reports tomorrow not ready before publication", () => {
    const m = T.parse(demo);
    assert.equal(m.prices.length, 96);
    assert.equal(m.tomorrowReady, false);
    assert.equal(m.currency, "SEK");
    assert.equal(m.home.name, "Vitahuset");
});

test("parse accepts a JSON string body", () => {
    assert.equal(T.parse(JSON.stringify(demo)).prices.length, 96);
});

test("parse sums consumption", () => {
    const m = T.parse(demo);
    assert.equal(m.consumption.hours, 24);
    const sum = demo.data.viewer.homes[0].consumption.nodes.reduce((s, n) => s + n.consumption, 0);
    assert.ok(Math.abs(m.consumption.kwh - sum) < 1e-9);
});

test("parse picks a home by id and errors on an unknown one", () => {
    assert.equal(T.parse(demo, demo.data.viewer.homes[0].id).home.id, demo.data.viewer.homes[0].id);
    assert.equal(T.parse(demo, "nope").error, "No home with a subscription");
});

test("parse surfaces GraphQL errors and garbage", () => {
    assert.equal(T.parse({ errors: [{ message: "Unauthorized" }] }).error, "Unauthorized");
    assert.equal(T.parse("<html>").error, "Bad response");
    assert.equal(T.parse({ data: { viewer: { homes: [] } } }).error, "No home with a subscription");
});

test("parse tolerates null consumption entries", () => {
    const r = clone(demo);
    r.data.viewer.homes[0].consumption.nodes[0].consumption = null;
    assert.equal(T.parse(r).consumption.hours, 23);
});

test("current finds the quarter-hour containing now", () => {
    const m = T.parse(demo);
    const c = T.current(m.prices, NOW);
    assert.equal(c.t, Date.parse("2026-11-11T12:45:00+01:00"));
    assert.equal(c.level, "VERY_EXPENSIVE");
    assert.equal(T.current(m.prices, Date.parse("2026-11-11T12:45:00+01:00")).t, c.t);
    assert.equal(T.current(m.prices, Date.parse("2026-11-11T12:44:59+01:00")).t, Date.parse("2026-11-11T12:30:00+01:00"));
});

test("current is null outside the known range", () => {
    const m = T.parse(demo);
    assert.equal(T.current(m.prices, Date.parse("2026-11-12T00:00:00+01:00")), null);
});

test("current works for hourly slots", () => {
    const hourly = [0, 1, 2].map((h) => ({ t: Date.parse("2026-11-11T0" + h + ":00:00+01:00"), total: h, day: "today" }));
    assert.equal(T.current(hourly, Date.parse("2026-11-11T01:59:00+01:00")).total, 1);
});

test("stats cover today only, cheapest upcoming spans tomorrow", () => {
    const m = T.parse(withTomorrow());
    const s = T.stats(m.prices, NOW);
    const today = m.prices.filter((p) => p.day === "today").map((p) => p.total);
    assert.equal(s.min.total, Math.min(...today));
    assert.equal(s.max.total, Math.max(...today));
    assert.ok(Math.abs(s.avg - today.reduce((a, b) => a + b, 0) / today.length) < 1e-9);
    assert.ok(s.cheapestUpcoming.t + 900000 > NOW);
});

test("stats cheapest upcoming skips slots already over", () => {
    const m = T.parse(demo);
    const s = T.stats(m.prices, Date.parse("2026-11-11T23:50:00+01:00"));
    assert.equal(s.cheapestUpcoming.t, Date.parse("2026-11-11T23:45:00+01:00"));
});

test("levelColor maps every Tibber level", () => {
    const want = { VERY_CHEAP: "success", CHEAP: "success", NORMAL: "surfaceText", EXPENSIVE: "warning", VERY_EXPENSIVE: "error", "": "surfaceText" };
    for (const [level, color] of Object.entries(want)) assert.equal(T.levelColor(level), color);
});

test("fmtPrice shows whole currency with two decimals or the minor unit rounded", () => {
    assert.equal(T.fmtPrice(5.2092), "5.21");
    assert.equal(T.fmtPrice(0), "0.00");
    assert.equal(T.fmtPrice(5.2092, true), "521");
    assert.equal(T.fmtPrice(-0.456, true), "-46");
});

test("unit names the minor unit per currency and falls back to the code", () => {
    assert.equal(T.unit("SEK", false), "SEK/kWh");
    assert.equal(T.unit("SEK", true), "öre/kWh");
    assert.equal(T.unit("NOK", true), "øre/kWh");
    assert.equal(T.unit("EUR", true), "ct/kWh");
    assert.equal(T.unit("GBP", true), "GBP/kWh");
    assert.equal(T.unitShort("SEK", true), "öre");
    assert.equal(T.unitShort("SEK", false), "SEK");
});

test("spotUrl builds the per-day area URL and rejects unknown areas", () => {
    const d = new Date(2026, 10, 5);
    assert.equal(T.spotUrl("SE3", d), "https://www.elprisetjustnu.se/api/v1/prices/2026/11-05_SE3.json");
    assert.equal(T.spotUrl("NO1", d), "https://www.hvakosterstrommen.no/api/v1/prices/2026/11-05_NO1.json");
    assert.equal(T.spotUrl("SE3", d, "http://x"), "http://x/api/v1/prices/2026/11-05_SE3.json");
    assert.equal(T.spotUrl("DK1", d), "");
});

const spotDay = (day, values) =>
    values.map((v, h) => ({
        SEK_per_kWh: v,
        EUR_per_kWh: v / 11,
        time_start: new Date(2026, 10, day, h).toISOString(),
        time_end: new Date(2026, 10, day, h + 1).toISOString(),
    }));

test("parseSpot uses the area currency, derives levels from the average and flags tomorrow", () => {
    const m = T.parseSpot("SE3", spotDay(11, [1, 1, 1, 3]), spotDay(12, [1, 1]));
    assert.equal(m.currency, "SEK");
    assert.equal(m.spot, true);
    assert.equal(m.prices.length, 6);
    assert.equal(m.tomorrowReady, true);
    assert.equal(m.prices[5].day, "tomorrow");
    assert.equal(m.prices[3].level, "VERY_EXPENSIVE");
    assert.equal(m.prices[0].level, "CHEAP");
    assert.equal(T.parseSpot("SE3", spotDay(11, [1, 1])).tomorrowReady, false);
});

test("parseSpot levels use Tibber's thresholds against the trailing 72 h average", () => {
    const flat = (day) => spotDay(day, Array.from({ length: 24 }, () => 1));
    const now = new Date(2026, 10, 11, 12).getTime();
    const today = Array.from({ length: 24 }, () => 1);
    [today[12], today[13], today[14], today[15], today[16]] = [0.5, 0.85, 1, 1.2, 1.5];
    const m = T.parseSpot("SE3", spotDay(11, today), null, [flat(8), flat(9), flat(10)], now);
    assert.equal(m.baseline, 1);
    assert.deepEqual([12, 13, 14, 15, 16].map((h) => m.prices[h].level), [
        "VERY_CHEAP", "CHEAP", "NORMAL", "EXPENSIVE", "VERY_EXPENSIVE",
    ]);
});

test("parseSpot without history falls back to today's average", () => {
    const m = T.parseSpot("SE3", spotDay(11, [1, 1, 1, 3]), null, [], new Date(2026, 10, 11, 0).getTime());
    assert.equal(m.baseline, 1.5);
    assert.equal(m.prices[3].level, "VERY_EXPENSIVE");
});

test("parse takes the baseline from Tibber's 72 h range, or 0 when absent", () => {
    assert.equal(T.parse(demo).baseline, 0);
    const r = clone(demo);
    r.data.viewer.homes[0].currentSubscription.priceInfoRange = { nodes: [{ total: 1 }, { total: 2 }] };
    assert.equal(T.parse(r).baseline, 1.5);
});

const enyaq = {
    info: { name: "Enyaq", brand: "Škoda", model: "Enyaq" },
    attributes: [{ id: "isOnline", value: true }],
    capabilities: [
        { id: "storage.stateOfCharge", value: 70, unit: "%" },
        { id: "storage.targetStateOfCharge", value: 80, unit: "%" },
        { id: "range.remaining", value: 256000, unit: "m" },
        { id: "connector.status", value: "disconnected", unit: null },
        { id: "charging.status", value: "idle", unit: null },
    ],
    status: { lastSeen: "2026-11-16T10:04:41.3134738+01:00" },
};
const dummy = { info: { name: "Gäst", brand: "Tibber", model: "Dummy" }, capabilities: [{ id: "storage.stateOfCharge", value: 50 }] };
const charger = { info: { name: "go-e", brand: "GoE", model: "Gemini" }, capabilities: [{ id: "charging.status", value: "idle" }] };

test("pickCar defaults to the first real car, converts range to km and reads plug and charge state", () => {
    const { car: c, found } = T.pickCar([dummy, charger, enyaq], "");
    assert.deepEqual([...found], ["Enyaq"]);
    assert.equal(c.brand, "Škoda");
    assert.equal(c.name, "Enyaq");
    assert.equal(c.soc, 70);
    assert.equal(c.target, 80);
    assert.equal(c.rangeKm, 256);
    assert.equal(c.plugged, false);
    assert.equal(c.charging, false);
    assert.equal(c.online, true);
    assert.equal(c.lastSeen, Date.parse("2026-11-16T10:04:41.3134738+01:00"));
});

test("pickCar sees a plugged-in charging car, accepts JSON strings, and finds no car without one", () => {
    const live = clone(enyaq);
    live.capabilities[3].value = "connected";
    live.capabilities[4].value = "charging";
    const c = T.pickCar([JSON.stringify(live)], "").car;
    assert.equal(c.plugged, true);
    assert.equal(c.charging, true);
    assert.equal(T.pickCar([dummy, charger], "").car, null);
    assert.equal(T.pickCar([], "").car, null);
});

test("pickCar matches by name, model or id ignoring case, and never falls back when a name is set", () => {
    const other = { id: "d-2", info: { name: "Family car", brand: "Volvo", model: "EX30" }, capabilities: [{ id: "storage.stateOfCharge", value: 40 }] };
    const both = [{ ...enyaq, id: "d-1" }, other];
    assert.equal(T.pickCar(both, "").car.name, "Enyaq");
    assert.equal(T.pickCar(both, " family CAR ").car.soc, 40);
    assert.equal(T.pickCar(both, "ex30").car.soc, 40);
    assert.equal(T.pickCar(both, "d-2").car.soc, 40);
    const miss = T.pickCar(both, "tesla");
    assert.equal(miss.car, null);
    assert.deepEqual([...miss.found], ["Enyaq", "Family car"]);
});

test("authUrl carries the client, redirect, scopes and state", () => {
    const u = T.authUrl("abc", "st8");
    assert.ok(u.startsWith("https://thewall.tibber.com/connect/authorize?"));
    for (const part of ["response_type=code", "client_id=abc", "state=st8", "redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback", "data-api-vehicles-read", "offline_access"])
        assert.ok(u.includes(part), part);
    assert.ok(!u.includes("data-api-prices-read"));
});

test("parseRedirect returns the code only for a matching state and explains every failure", () => {
    const ok = "http://localhost:8765/callback?code=C0DE-1&state=st8&session_state=x&iss=https%3A%2F%2Fthewall.tibber.com";
    assert.equal(T.parseRedirect(ok, "st8").code, "C0DE-1");
    assert.equal(T.parseRedirect("  " + ok + "\n", "st8").code, "C0DE-1");
    assert.match(T.parseRedirect(ok, "other").error, /started elsewhere/);
    assert.match(T.parseRedirect(ok, "").error, /started elsewhere/);
    assert.match(T.parseRedirect("http://localhost:8765/callback", "st8").error, /whole address/);
    assert.match(T.parseRedirect("http://localhost:8765/callback?state=st8", "st8").error, /no login code/);
    assert.equal(T.parseRedirect("http://localhost:8765/callback?error=access_denied&error_description=No+thanks&state=st8", "st8").error, "No thanks");
    assert.equal(T.parseRedirect("http://localhost:8765/callback?error=access_denied&state=st8", "st8").error, "The login was cancelled");
});

test("tokenBody builds the code and refresh requests", () => {
    const code = new URLSearchParams(T.tokenBody("cid", "s e/cret", { code: "C1" }));
    assert.equal(code.get("grant_type"), "authorization_code");
    assert.equal(code.get("code"), "C1");
    assert.equal(code.get("redirect_uri"), "http://localhost:8765/callback");
    assert.equal(code.get("client_secret"), "s e/cret");
    const refresh = new URLSearchParams(T.tokenBody("cid", "sec", { refresh: "R1" }));
    assert.equal(refresh.get("grant_type"), "refresh_token");
    assert.equal(refresh.get("refresh_token"), "R1");
    assert.equal(refresh.get("code"), null);
});

test("tokensFrom stores expiry, keeps the old refresh token when none is returned and flags revoked grants", () => {
    const t = T.tokensFrom({ access_token: "A", refresh_token: "R", expires_in: 3600 }, 1000);
    assert.equal(t.access_token, "A");
    assert.equal(t.refresh_token, "R");
    assert.equal(t.expires_at, 1000 + 3600000);
    assert.equal(T.tokensFrom(JSON.stringify({ access_token: "B" }), 0, { refresh_token: "OLD" }).refresh_token, "OLD");
    const bad = T.tokensFrom({ error: "invalid_grant", error_description: "expired" }, 0);
    assert.equal(bad.revoked, true);
    assert.equal(bad.error, "expired");
    assert.equal(T.tokensFrom({ error: "invalid_client" }, 0).revoked, false);
    assert.match(T.tokensFrom({ error: "invalid_client" }, 0).error, /client ID or secret/);
    assert.match(T.tokensFrom({ error: "invalid_grant" }, 0).error, /click Open Tibber login/);
    assert.equal(T.tokensFrom({ error: "weird" }, 0).error, "weird");
    assert.equal(T.tokensFrom("garbage", 0).error, "Bad response");
});

test("needsRefresh asks five minutes ahead and when tokens are missing", () => {
    assert.equal(T.needsRefresh(null, 0), true);
    assert.equal(T.needsRefresh({ access_token: "A", expires_at: 400000 }, 0), false);
    assert.equal(T.needsRefresh({ access_token: "A", expires_at: 299999 }, 0), true);
});

test("carStatus walks through setup, connect, car, reconnect, notfound, nocar, error and loading", () => {
    const base = { enabled: true, clientId: "c", hasSecret: true, tokens: { refresh_token: "R" }, found: [], fetched: true };
    assert.equal(T.carStatus({ ...base, enabled: false }), "off");
    assert.equal(T.carStatus({ ...base, clientId: "" }), "setup");
    assert.equal(T.carStatus({ ...base, hasSecret: false }), "setup");
    assert.equal(T.carStatus({ ...base, tokens: null }), "connect");
    assert.equal(T.carStatus({ ...base, revoked: true }), "reconnect");
    assert.equal(T.carStatus({ ...base, car: {} }), "car");
    assert.equal(T.carStatus({ ...base, name: "x", found: ["Enyaq"] }), "notfound");
    assert.equal(T.carStatus(base), "nocar");
    assert.equal(T.carStatus({ ...base, error: "HTTP 500" }), "error");
    assert.equal(T.carStatus({ ...base, fetched: false }), "loading");
});

test("daysAgo counts local calendar days", () => {
    const now = new Date(2026, 10, 16, 1).getTime();
    assert.equal(T.daysAgo(new Date(2026, 10, 16, 0, 5).getTime(), now), 0);
    assert.equal(T.daysAgo(new Date(2026, 10, 15, 23, 55).getTime(), now), 1);
    assert.equal(T.daysAgo(new Date(2026, 10, 13, 12).getTime(), now), 3);
});

test("parseSpot picks the NOK field for Norwegian areas and rejects bad input", () => {
    const no = [{ NOK_per_kWh: 1.5, time_start: new Date(2026, 10, 11, 0).toISOString() }];
    const m = T.parseSpot("NO2", no);
    assert.equal(m.currency, "NOK");
    assert.equal(m.prices[0].total, 1.5);
    assert.equal(T.parseSpot("XX9", no).error, "Unknown price area");
    assert.equal(T.parseSpot("SE3", "garbage").error, "No prices");
});

test("yTicks picks round gridlines in the displayed unit", () => {
    const labels = (lo, hi, minor) => [...T.yTicks(lo, hi, minor)].map((t) => t.label);
    assert.deepEqual(labels(0, 5.48, false), ["0", "1", "2", "3", "4", "5", "6"]);
    assert.deepEqual(labels(0, 5.48, true), ["0", "100", "200", "300", "400", "500", "600"]);
    assert.deepEqual(labels(0, 2.8737, true), ["0", "100", "200", "300"]);
    assert.deepEqual(labels(0, 0.4, false), ["0.0", "0.1", "0.2", "0.3", "0.4"]);
    assert.deepEqual([...T.yTicks(0, 5.48, true)].map((t) => t.v), [0, 1, 2, 3, 4, 5, 6]);
    assert.deepEqual(labels(-0.45, 5.48, false), ["-2", "0", "2", "4", "6"]);
});

test("ticks marks every sixth hour on the hour", () => {
    const m = T.parseSpot("SE3", spotDay(11, Array.from({ length: 24 }, () => 1)));
    assert.deepEqual([...T.ticks(m.prices)].map((t) => t.label), ["00", "06", "12", "18"]);
    assert.deepEqual([...T.ticks(m.prices)].map((t) => t.i), [0, 6, 12, 18]);
});

test("nextFetch waits the interval after success and a minute after failure", () => {
    assert.equal(T.nextFetch(1000, true, 15), 1000 + 15 * 60000);
    assert.equal(T.nextFetch(1000, false, 15), 1000 + 60000);
});

test("range includes zero and handles negative prices", () => {
    assert.deepEqual({ ...T.range([{ total: 2 }, { total: 5 }]) }, { lo: 0, hi: 5 });
    assert.deepEqual({ ...T.range([{ total: -1 }, { total: 3 }]) }, { lo: -1, hi: 3 });
});

test("range never collapses to zero height", () => {
    assert.deepEqual({ ...T.range([{ total: 0 }]) }, { lo: 0, hi: 1 });
    assert.deepEqual({ ...T.range([{ total: -2 }, { total: -1 }]) }, { lo: -2, hi: 0 });
});
