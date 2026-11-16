"""Mock Tibber API for tests/render.sh. The bearer token selects the behaviour; timestamps are
rewritten to the real local "today" so the current slot always exists."""
import json
import re
import sys
from datetime import date, datetime, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

port, fixture, requests_log = int(sys.argv[1]), sys.argv[2], sys.argv[3]
DEMO_TOKEN = sys.argv[4]
base = json.load(open(fixture))


def iso(dt):
    return dt.isoformat(timespec="milliseconds")


def build(token):
    r = json.loads(json.dumps(base))
    home = r["data"]["viewer"]["homes"][0]
    info = home["currentSubscription"]["priceInfo"]
    home["currentSubscription"]["priceInfoRange"] = {"nodes": [{"total": 3.0}] * 72}
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
    def data_api(self):
        """Tibber Data API: only the bearer token "carok" is accepted."""
        if self.headers.get("Authorization", "") != "Bearer carok":
            self.send_response(401)
            self.end_headers()
            return
        seen = (datetime.now().astimezone() - timedelta(minutes=10)).isoformat(timespec="seconds")
        devices = {
            "d-goe": {"info": {"name": "go-e gemini", "brand": "GoE", "model": "Gemini Flex"}, "attributes": [], "status": {"lastSeen": seen},
                      "capabilities": [{"id": "charging.status", "value": "idle", "unit": None}]},
            "d-enyaq": {"info": {"name": "Enyaq", "brand": "Škoda", "model": "Enyaq"}, "attributes": [{"id": "isOnline", "value": True}], "status": {"lastSeen": seen},
                        "capabilities": [
                            {"id": "storage.stateOfCharge", "value": 70, "unit": "%"},
                            {"id": "storage.targetStateOfCharge", "value": 80, "unit": "%"},
                            {"id": "range.remaining", "value": 256000, "unit": "m"},
                            {"id": "connector.status", "value": "disconnected", "unit": None},
                            {"id": "charging.status", "value": "idle", "unit": None}]},
            "d-family": {"info": {"name": "Family car", "brand": "Volvo", "model": "EX30"}, "attributes": [{"id": "isOnline", "value": True}], "status": {"lastSeen": seen},
                         "capabilities": [
                             {"id": "storage.stateOfCharge", "value": 40, "unit": "%"},
                             {"id": "storage.targetStateOfCharge", "value": 90, "unit": "%"},
                             {"id": "range.remaining", "value": 120000, "unit": "m"},
                             {"id": "connector.status", "value": "connected", "unit": None},
                             {"id": "charging.status", "value": "charging", "unit": None}]},
            "d-dummy": {"info": {"name": "Gäst", "brand": "Tibber", "model": "Dummy"}, "attributes": [{"id": "isOnline", "value": False}], "status": {"lastSeen": seen},
                        "capabilities": [{"id": "storage.stateOfCharge", "value": 50, "unit": "%"}]},
        }
        parts = self.path.split("/")
        if self.path == "/v1/homes":
            body = {"homes": [{"id": "home-1", "name": "Vitahuset"}]}
        elif self.path == "/v1/homes/home-1/devices":
            body = {"devices": [{"id": k, "info": v["info"]} for k, v in devices.items()]}
        elif len(parts) == 6 and parts[:5] == ["", "v1", "homes", "home-1", "devices"] and parts[5] in devices:
            body = {"id": parts[5], **devices[parts[5]]}
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_GET(self):
        with open(requests_log, "a") as f:
            f.write("GET " + self.path + "\n")
        if self.path.startswith("/v1/homes"):
            return self.data_api()
        m = re.fullmatch(r"/api/v1/prices/(\d{4})/(\d\d)-(\d\d)_((SE|NO)\d)\.json", self.path)
        offset = (date(*map(int, m.groups()[:3])) - date.today()).days if m else None
        # Like the real services: Sweden publishes tomorrow already, Norway does not in this mock.
        if offset not in (-3, -2, -1, 0, 1) or (offset == 1 and m.group(5) == "NO"):
            self.send_response(404)
            self.end_headers()
            return
        cur = {"SE": "SEK", "NO": "NOK"}[m.group(5)]
        totals = [p["total"] for p in base["data"]["viewer"]["homes"][0]["currentSubscription"]["priceInfo"]["today"]]
        step = 15 if cur == "SEK" else 60
        midnight = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=offset)
        body = [
            {
                f"{cur}_per_kWh": round(totals[i * step // 15] * (0.7 if offset == 1 else 1), 5),
                "time_start": (midnight + timedelta(minutes=step * i)).isoformat(timespec="seconds"),
                "time_end": (midnight + timedelta(minutes=step * (i + 1))).isoformat(timespec="seconds"),
            }
            for i in range(24 * 60 // step)
        ]
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def token(self, body):
        """Tibber OAuth token endpoint: the code GOODCODE and the refresh tokens r-ok (rotates to r-next) or r-revoked."""
        f = parse_qs(body)
        grant = f.get("grant_type", [""])[0]
        with open(requests_log, "a") as log:
            log.write("POST /connect/token grant=" + grant + "\n")
        client = f.get("client_id") == ["cid-test"] and f.get("client_secret") == ["sekret"]
        if client and grant == "authorization_code" and f.get("code") == ["GOODCODE"]:
            status, out = 200, {"access_token": "carok", "refresh_token": "r1", "expires_in": 3600}
        elif client and grant == "refresh_token" and f.get("refresh_token") == ["r-ok"]:
            status, out = 200, {"access_token": "carok", "refresh_token": "r-next", "expires_in": 3600}
        else:
            status, out = 400, {"error": "invalid_grant" if client else "invalid_client"}
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(out).encode())

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        if self.path == "/connect/token":
            return self.token(body)
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
