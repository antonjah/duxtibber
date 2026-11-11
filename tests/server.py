"""Mock Tibber API for tests/render.sh. The bearer token selects the behaviour; timestamps are
rewritten to the real local "today" so the current slot always exists."""
import json
import re
import sys
from datetime import date, datetime, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer

port, fixture, requests_log = int(sys.argv[1]), sys.argv[2], sys.argv[3]
DEMO_TOKEN = sys.argv[4]
base = json.load(open(fixture))


def iso(dt):
    return dt.isoformat(timespec="milliseconds")


def build(token):
    r = json.loads(json.dumps(base))
    home = r["data"]["viewer"]["homes"][0]
    info = home["currentSubscription"]["priceInfo"]
    midnight = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    for i, p in enumerate(info["today"]):
        p["startsAt"] = iso(midnight + timedelta(minutes=15 * i))
    if token != DEMO_TOKEN:
        # Tomorrow is published: a squeezed copy of today so the two halves differ visibly.
        info["tomorrow"] = [
            {**p, "startsAt": iso(midnight + timedelta(days=1, minutes=15 * i)), "total": round(p["total"] * 0.7, 4)}
            for i, p in enumerate(info["today"])
        ]
    if token == "negative":
        for p in info["today"][32:44]:
            p["total"], p["level"] = -0.45, "VERY_CHEAP"
    start = datetime.now().astimezone().replace(minute=0, second=0, microsecond=0) - timedelta(hours=24)
    for i, n in enumerate(home["consumption"]["nodes"]):
        n["from"], n["to"] = iso(start + timedelta(hours=i)), iso(start + timedelta(hours=i + 1))
    return r


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(requests_log, "a") as f:
            f.write("GET " + self.path + "\n")
        m = re.fullmatch(r"/api/v1/prices/(\d{4})/(\d\d)-(\d\d)_((SE|NO)\d)\.json", self.path)
        offset = (date(*map(int, m.groups()[:3])) - date.today()).days if m else None
        # Like the real services: Sweden publishes tomorrow already, Norway does not in this mock.
        if offset not in (0, 1) or (offset == 1 and m.group(5) == "NO"):
            self.send_response(404)
            self.end_headers()
            return
        cur = {"SE": "SEK", "NO": "NOK"}[m.group(5)]
        totals = [p["total"] for p in base["data"]["viewer"]["homes"][0]["currentSubscription"]["priceInfo"]["today"]]
        step = 15 if cur == "SEK" else 60
        midnight = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=offset)
        body = [
            {
                f"{cur}_per_kWh": round(totals[i * step // 15] * (0.7 if offset else 1), 5),
                "time_start": (midnight + timedelta(minutes=step * i)).isoformat(timespec="seconds"),
                "time_end": (midnight + timedelta(minutes=step * (i + 1))).isoformat(timespec="seconds"),
            }
            for i in range(24 * 60 // step)
        ]
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        auth = self.headers.get("Authorization", "")
        token = auth[7:] if auth.startswith("Bearer ") else ""
        with open(requests_log, "a") as f:
            f.write(token + "\n")
        ok = token in (DEMO_TOKEN, "good", "negative")
        body = build(token) if ok else {"errors": [{"message": "Unauthorized"}]}
        self.send_response(200 if ok else 401)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", port), H).serve_forever()
