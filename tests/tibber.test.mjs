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
