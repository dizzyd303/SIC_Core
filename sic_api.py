#!/usr/bin/env python3
"""
sic_api.py — SIC Platform API (zero dependencies, pure Python stdlib)

Usage:
    python3 sic_api.py
    python3 sic_api.py --host 0.0.0.0 --port 8000

Endpoints:
    GET  /                        — status
    GET  /modules                 — list available modules
    POST /run                     — launch a module
    GET  /runs                    — list all past runs
    GET  /runs/{run_id}           — run metadata
    GET  /runs/{run_id}/stream    — live log (newline-delimited, poll-friendly)
    GET  /runs/{run_id}/report    — markdown report
    GET  /runs/{run_id}/files     — list output files
    DELETE /runs/{run_id}         — delete a run

No pip. No venv. No dependencies. Just Python 3.6+.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# ── Config ───────────────────────────────────────────────────────────────────
SIC_HOME     = Path(os.environ.get("SIC_HOME", Path.home() / ".sic"))
SIC_RUNS_DIR = SIC_HOME / "runs"
SIC_INDEX    = SIC_HOME / "runs.index"

# Where to look for module scripts
SIC_SEARCH_PATHS = [
    Path.home() / "sic-platform",
    Path("/usr/local/bin"),
    Path("/usr/local/lib"),
    Path.home(),
]

ALLOWED_MODULES = [
    "SIC_Security",
    "SIC_Skip",
    "SIC_Diagnostics",
    "SIC_COPE",
    "SIC_Cloud_Security",
    "SIC_Stocks",
]

SIC_HOME.mkdir(parents=True, exist_ok=True)
SIC_RUNS_DIR.mkdir(parents=True, exist_ok=True)
SIC_INDEX.touch(exist_ok=True)

STRIP_ANSI = re.compile(r'\x1b\[[0-9;]*m')

# ── Helpers ───────────────────────────────────────────────────────────────────

def find_module(module: str):
    """Return path to module script or None."""
    for base in SIC_SEARCH_PATHS:
        p = base / f"{module}.sh"
        if p.exists():
            return p
    return None


def read_index():
    """Parse runs.index → list of dicts, newest first."""
    runs = []
    if not SIC_INDEX.exists():
        return runs
    for line in SIC_INDEX.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("|", 5)
        if len(parts) < 6:
            continue
        run_id, module, target, ts, status, goal = parts
        run_dir = SIC_RUNS_DIR / run_id
        runs.append({
            "run_id":           run_id,
            "module":           module,
            "target":           target,
            "timestamp":        ts,
            "status":           status,
            "goal":             goal,
            "run_dir":          str(run_dir),
            "report_available": (run_dir / "report.md").exists(),
        })
    return list(reversed(runs))


def get_run(run_id: str):
    """Return run dict or None."""
    for r in read_index():
        if r["run_id"] == run_id:
            return r
    return None


def update_index_status(run_id: str, status: str):
    if not SIC_INDEX.exists():
        return
    lines = SIC_INDEX.read_text().splitlines()
    updated = []
    for line in lines:
        if line.startswith(run_id + "|"):
            parts = line.split("|", 5)
            if len(parts) == 6:
                parts[4] = status
                line = "|".join(parts)
        updated.append(line)
    SIC_INDEX.write_text("\n".join(updated) + "\n")


def run_module_bg(module: str, goal: str, env_override: dict):
    """Run a SIC module in a background thread, stream output to live.log."""
    script = find_module(module)
    if not script:
        return

    env = os.environ.copy()
    env["AUTO_RUN"]  = "1"
    env["SIC_HOME"]  = str(SIC_HOME)
    for k, v in env_override.items():
        env[k] = str(v)

    proc = subprocess.Popen(
        ["bash", str(script), goal],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        text=True,
    )

    # Wait for sic_core to create the run dir and index entry
    live_log = None
    for _ in range(30):
        time.sleep(0.5)
        for run in read_index():
            if run["module"] == module and run["status"] == "running":
                lp = Path(run["run_dir"]) / "live.log"
                live_log = lp
                break
        if live_log:
            break

    if live_log:
        live_log.parent.mkdir(parents=True, exist_ok=True)
        with open(live_log, "w") as lf:
            for line in proc.stdout:
                clean = STRIP_ANSI.sub("", line)
                lf.write(clean)
                lf.flush()
    else:
        proc.communicate()

    proc.wait()


# ── Request handler ───────────────────────────────────────────────────────────

class SICHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        # Clean up the default noisy logging
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"[{ts}] {self.command} {self.path} — {args[1]}")

    def send_json(self, code: int, data):
        body = json.dumps(data, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, code: int, text: str):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, code: int, detail: str):
        self.send_json(code, {"error": detail})

    def do_OPTIONS(self):
        # CORS preflight
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length).decode() if length else ""

    def do_GET(self):
        parsed = urlparse(self.path)
        path   = parsed.path.rstrip("/")
        parts  = [p for p in path.split("/") if p]

        # GET /
        if path in ("", "/"):
            self.send_text(200, (
                "SIC Platform API v1.0 (stdlib edition)\n"
                "Routes:\n"
                "  GET  /modules\n"
                "  POST /run\n"
                "  GET  /runs\n"
                "  GET  /runs/{run_id}\n"
                "  GET  /runs/{run_id}/stream\n"
                "  GET  /runs/{run_id}/report\n"
                "  GET  /runs/{run_id}/files\n"
                "  DELETE /runs/{run_id}\n"
            ))

        # GET /modules
        elif path == "/modules":
            result = []
            for m in ALLOWED_MODULES:
                script = find_module(m)
                result.append({
                    "module": m,
                    "found":  script is not None,
                    "path":   str(script) if script else None,
                })
            self.send_json(200, result)

        # GET /runs
        elif path == "/runs":
            qs     = parse_qs(parsed.query)
            limit  = int(qs.get("limit", ["50"])[0])
            module = qs.get("module", [None])[0]
            runs   = read_index()
            if module:
                runs = [r for r in runs if r["module"] == module]
            self.send_json(200, runs[:limit])

        # GET /runs/last
        elif path == "/runs/last":
            runs = read_index()
            if not runs:
                self.send_error_json(404, "No runs yet")
            else:
                self.send_json(200, runs[0])

        # GET /runs/{run_id}
        elif len(parts) == 2 and parts[0] == "runs":
            run = get_run(parts[1])
            if not run:
                self.send_error_json(404, f"Run not found: {parts[1]}")
            else:
                self.send_json(200, run)

        # GET /runs/{run_id}/stream
        elif len(parts) == 3 and parts[0] == "runs" and parts[2] == "stream":
            self._stream_log(parts[1])

        # GET /runs/{run_id}/report
        elif len(parts) == 3 and parts[0] == "runs" and parts[2] == "report":
            run = get_run(parts[1])
            if not run:
                self.send_error_json(404, "Run not found")
                return
            rp = Path(run["run_dir"]) / "report.md"
            if not rp.exists():
                self.send_error_json(404, "Report not ready yet")
            else:
                self.send_text(200, rp.read_text())

        # GET /runs/{run_id}/files
        elif len(parts) == 3 and parts[0] == "runs" and parts[2] == "files":
            run = get_run(parts[1])
            if not run:
                self.send_error_json(404, "Run not found")
                return
            rd = Path(run["run_dir"])
            files = {}
            for sub in ["vuln", "outputs", "scripts"]:
                p = rd / sub
                if p.exists():
                    files[sub] = sorted(f.name for f in p.iterdir() if f.is_file())
            self.send_json(200, {"run_id": parts[1], "run_dir": str(rd), "files": files})

        else:
            self.send_error_json(404, f"Unknown route: {path}")

    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/")

        # POST /run
        if path == "/run":
            try:
                body = json.loads(self.read_body())
            except json.JSONDecodeError:
                self.send_error_json(400, "Invalid JSON body")
                return

            module = body.get("module", "")
            goal   = body.get("goal",   "")
            env    = body.get("env",    {})

            if not module or not goal:
                self.send_error_json(400, "Both 'module' and 'goal' are required")
                return
            if module not in ALLOWED_MODULES:
                self.send_error_json(400, f"Unknown module '{module}'. Allowed: {ALLOWED_MODULES}")
                return
            if not find_module(module):
                self.send_error_json(404, f"{module}.sh not found in search paths")
                return

            t = threading.Thread(
                target=run_module_bg,
                args=(module, goal, env),
                daemon=True,
            )
            t.start()

            self.send_json(202, {
                "status":   "launched",
                "module":   module,
                "goal":     goal,
                "message":  "Poll GET /runs to find your run once it appears",
                "runs_url": "/runs",
            })

        else:
            self.send_error_json(404, f"Unknown POST route: {path}")

    def do_DELETE(self):
        path   = urlparse(self.path).path.rstrip("/")
        parts  = [p for p in path.split("/") if p]

        # DELETE /runs/{run_id}
        if len(parts) == 2 and parts[0] == "runs":
            run_id = parts[1]
            run = get_run(run_id)
            if not run:
                self.send_error_json(404, f"Run not found: {run_id}")
                return
            rd = Path(run["run_dir"])
            if rd.exists():
                shutil.rmtree(rd)
            # Remove from index
            lines = [l for l in SIC_INDEX.read_text().splitlines()
                     if not l.startswith(run_id + "|")]
            SIC_INDEX.write_text("\n".join(lines) + "\n")
            self.send_json(200, {"deleted": run_id})
        else:
            self.send_error_json(404, f"Unknown DELETE route: {path}")

    def _stream_log(self, run_id: str):
        """
        Stream live.log line by line as plain text.
        Client can poll this or read it with a simple fetch/curl.
        Each line is newline-terminated. Final line is: [SIC_STREAM_DONE]
        """
        run = get_run(run_id)
        if not run:
            self.send_error_json(404, f"Run not found: {run_id}")
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        live_log = Path(run["run_dir"]) / "live.log"

        # Wait up to 15s for live.log to appear
        waited = 0
        while not live_log.exists() and waited < 15:
            self._write_chunk("[waiting for run to start...]\n")
            time.sleep(1)
            waited += 1

        if not live_log.exists():
            self._write_chunk("[live.log not found — run may have failed]\n")
            self._write_chunk("[SIC_STREAM_DONE]\n")
            self._write_chunk("")
            return

        with open(live_log) as f:
            idle = 0
            while True:
                line = f.readline()
                if line:
                    self._write_chunk(line)
                    idle = 0
                else:
                    current = get_run(run_id)
                    if current and current["status"] == "complete":
                        self._write_chunk("[SIC_STREAM_DONE]\n")
                        break
                    idle += 1
                    if idle > 180:
                        self._write_chunk("[SIC_STREAM_TIMEOUT]\n")
                        break
                    time.sleep(1)

        self._write_chunk("")  # end chunked transfer

    def _write_chunk(self, text: str):
        try:
            data = text.encode()
            self.wfile.write(f"{len(data):x}\r\n".encode())
            self.wfile.write(data)
            self.wfile.write(b"\r\n")
            self.wfile.flush()
        except BrokenPipeError:
            pass


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="SIC Platform API")
    parser.add_argument("--host", default="127.0.0.1",
                        help="Bind host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8000,
                        help="Bind port (default: 8000)")
    parser.add_argument("--public", action="store_true",
                        help="Shortcut for --host 0.0.0.0 (expose to network)")
    args = parser.parse_args()

    host = "0.0.0.0" if args.public else args.host

    print(f"""
╔══════════════════════════════════════════╗
║       SIC Platform API — stdlib          ║
║       Zero dependencies. Just Python.    ║
╚══════════════════════════════════════════╝
  Listening : http://{host}:{args.port}
  Runs dir  : {SIC_RUNS_DIR}
  Index     : {SIC_INDEX}

  Quick test:
    curl http://{host}:{args.port}/modules
    curl -X POST http://{host}:{args.port}/run \\
      -H 'Content-Type: application/json' \\
      -d '{{"module":"SIC_Security","goal":"recon example.com"}}'
    curl http://{host}:{args.port}/runs
""")

    server = HTTPServer((host, args.port), SICHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] SIC API stopped.")


if __name__ == "__main__":
    main()
