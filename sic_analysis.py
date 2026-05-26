# Created by SpYdA573 (Daniel Young)
#!/usr/bin/env python3
"""
SIC Analysis Engine — Confidence scoring, triangulation, and structured reporting.
Adds HackerGPT-style intelligence layers: source reliability, corroboration detection,
recency weighting, and structured findings with confidence levels.
"""
import json, os, re
from datetime import datetime, timezone

# ── Source Reliability Rankings ──
SOURCE_RELIABILITY = {
    "nmap":         {"rank": 95, "label": "High", "reason": "Direct network probe — port states are factual"},
    "nuclei":       {"rank": 80, "label": "High", "reason": "Template-based scanner with known signatures"},
    "testssl":      {"rank": 85, "label": "High", "reason": "Direct TLS handshake — cryptographic facts"},
    "whatweb":      {"rank": 70, "label": "Medium", "reason": "HTTP fingerprint — version detection can be inaccurate"},
    "ffuf":         {"rank": 60, "label": "Medium", "reason": "Web fuzzer — hits may be false positives without verification"},
    "whois":        {"rank": 75, "label": "High", "reason": "Registrar data — authoritative but may have privacy redaction"},
    "sherlock":     {"rank": 65, "label": "Medium", "reason": "Username search — relies on profile presence, can FP"},
    "theharvester": {"rank": 70, "label": "Medium", "reason": "Aggregator search — data freshness varies by source"},
    "rapidapi":     {"rank": 60, "label": "Medium", "reason": "Third-party API — reliability depends on upstream provider"},
    "github":       {"rank": 85, "label": "High", "reason": "Direct API query — authoritative for public repos"},
    "wikipedia":    {"rank": 50, "label": "Low", "reason": "User-edited content — not authoritative for intelligence"},
    "duckduckgo":   {"rank": 40, "label": "Low", "reason": "Search engine snippet — context may be incomplete"},
    "dns":          {"rank": 90, "label": "High", "reason": "Direct DNS resolution — authoritative record query"},
    "journalctl":   {"rank": 85, "label": "High", "reason": "System log — factual record of events"},
    "docker":       {"rank": 80, "label": "High", "reason": "Direct Docker API — factual container state"},
    "kubectl":      {"rank": 80, "label": "High", "reason": "Direct Kubernetes API — factual cluster state"},
    "ai_analysis":  {"rank": 55, "label": "Medium", "reason": "LLM-generated — may hallucinate, needs verification"},
    "phone_lookup": {"rank": 70, "label": "Medium", "reason": "Phone carrier/line data — depends on upstream DB freshness"},
    "leak_search":  {"rank": 65, "label": "Medium", "reason": "Breach database search — data age and accuracy vary"},
    "social_media": {"rank": 55, "label": "Medium", "reason": "Social media scrape — self-reported, may be outdated"},
    "court_records": {"rank": 80, "label": "High", "reason": "Public court records — factual but may not reflect current status"},
    "property_records": {"rank": 85, "label": "High", "reason": "County assessor data — authoritative for ownership"},
    "voter_records": {"rank": 75, "label": "High", "reason": "Voter registration — authoritative but requires filter"},
    "geolocation":   {"rank": 70, "label": "Medium", "reason": "IP geo or phone area code — approximate at best"},
    "name_frequency": {"rank": 60, "label": "Medium", "reason": "Statistical name distribution — probabilistic, not deterministic"},
}
DEFAULT_RANK = {"rank": 50, "label": "Medium", "reason": "Unknown source — reliability not assessed"}

def normalize_source(raw_source):
    s = raw_source.lower()
    if "nmap" in s: return "nmap"
    if "nuclei" in s: return "nuclei"
    if "testssl" in s: return "testssl"
    if "whatweb" in s: return "whatweb"
    if "ffuf" in s: return "ffuf"
    if "fuzz" in s: return "ffuf"
    if "whois" in s: return "whois"
    if "sherlock" in s: return "sherlock"
    if "harvester" in s or "theharvester" in s: return "theharvester"
    if "rapid" in s: return "rapidapi"
    if "github" in s: return "github"
    if "wiki" in s: return "wikipedia"
    if "duckduckgo" in s or "ddg" in s: return "duckduckgo"
    if "dns" in s or "dig" in s or "dnsx" in s: return "dns"
    if "journalctl" in s or "log" in s: return "journalctl"
    if "docker" in s: return "docker"
    if "kubectl" in s or "k8s" in s or "kube" in s: return "kubectl"
    if "ai" in s or "llm" in s or "analysis" in s or "threat" in s: return "ai_analysis"
    if "phone" in s or "lookup" in s: return "phone_lookup"
    if "leak" in s or "breach" in s: return "leak_search"
    if "social" in s or "facebook" in s or "linkedin" in s: return "social_media"
    if "court" in s or "record" in s: return "court_records"
    if "property" in s or "tax" in s or "assessor" in s: return "property_records"
    if "voter" in s or "registration" in s: return "voter_records"
    if "geo" in s or "location" in s or "area code" in s: return "geolocation"
    if "name" in s or "frequency" in s: return "name_frequency"
    return raw_source.lower().replace(".json","").replace(".txt","")

def score_source(source):
    canonical = normalize_source(source)
    return SOURCE_RELIABILITY.get(canonical, DEFAULT_RANK)

def _confidence_label(score):
    if score >= 85: return "High"
    elif score >= 60: return "Medium"
    return "Low"

def _overall_assessment(high, medium, low, corr_count):
    if high > medium + low and corr_count > 2: return "High confidence — multiple corroborated high-reliability sources"
    if high + medium > low * 2: return "Moderate confidence — mix of reliable and speculative sources"
    if corr_count > 0: return "Low confidence — some corroboration but sources are primarily speculative"
    return "Low confidence — no corroboration, mostly speculative sources"

# ── Finding ──
class Finding:
    def __init__(self, source, finding_type, value, context="", discovered_at=""):
        self.source = source
        self.source_info = score_source(source)
        self.finding_type = finding_type
        self.value = value
        self.context = context
        self.discovered_at = discovered_at or datetime.now(timezone.utc).isoformat()
    def to_dict(self):
        return {
            "source": self.source,
            "source_reliability": self.source_info["label"],
            "source_rank": self.source_info["rank"],
            "source_reason": self.source_info["reason"],
            "type": self.finding_type,
            "value": self.value,
            "context": self.context,
            "discovered_at": self.discovered_at,
        }

# ── Triangulation Engine ──
class TriangulationEngine:
    def __init__(self):
        self.findings = []

    def add_finding(self, finding):
        self.findings.append(finding)

    def load_from_directory(self, directory):
        if not os.path.isdir(directory): return
        for fname in sorted(os.listdir(directory)):
            fpath = os.path.join(directory, fname)
            if not os.path.isfile(fpath) or os.path.getsize(fpath) == 0: continue
            try:
                with open(fpath, "r", errors="replace") as f: content = f.read()
                self._parse_file(fname, content)
            except: pass

    def _parse_file(self, source, content):
        for line in content.split("\n")[:200]:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("=="): continue
            m = re.search(r"(\d+)/tcp\s+open\s+(\S+)", line)
            if m:
                self.add_finding(Finding(source, "open_port", f"{m.group(1)}/tcp ({m.group(2)})"))
                continue
            if len(line) < 200:
                self.add_finding(Finding(source, "raw_line", line))

    def add_raw(self, source, text):
        for line in text.strip().split("\n"):
            line = line.strip()
            if line and len(line) < 300:
                self.add_finding(Finding(source, "raw_line", line))

    def find_corroborations(self, min_sources=2):
        value_map = {}
        for f in self.findings:
            key = f"{f.finding_type}:{f.value}"
            value_map.setdefault(key, []).append(f)
        corroborated = []
        for key, matches in value_map.items():
            sources = set(m.source for m in matches)
            if len(sources) >= min_sources:
                max_rank = max(m.source_info["rank"] for m in matches)
                combined = min(100, max_rank + (len(sources) * 5))
                corroborated.append({
                    "finding": key,
                    "occurrences": len(matches),
                    "unique_sources": sorted(sources),
                    "combined_confidence": combined,
                    "confidence_level": _confidence_label(combined),
                })
        return sorted(corroborated, key=lambda x: -x["combined_confidence"])

    def confidence_summary(self):
        hi = sum(1 for f in self.findings if f.source_info["label"] == "High")
        med = sum(1 for f in self.findings if f.source_info["label"] == "Medium")
        lo = sum(1 for f in self.findings if f.source_info["label"] == "Low")
        srcs = {}
        for f in self.findings:
            srcs.setdefault(f.source, {"count": 0, "reliability": f.source_info["label"], "rank": f.source_info["rank"]})
            srcs[f.source]["count"] += 1
        corr = self.find_corroborations(2)
        return {
            "total_findings": len(self.findings),
            "by_reliability": {"High": hi, "Medium": med, "Low": lo},
            "source_breakdown": srcs,
            "corroborations": corr,
            "overall_assessment": _overall_assessment(hi, med, lo, len(corr)),
        }

    def generate_report(self, subject=""):
        s = self.confidence_summary()
        lines = []
        if subject: lines.append(f"## Intelligence Report: {subject}\n")
        lines.append("### Findings by Reliability\n")
        lines.append("| Reliability | Count | Interpretation |")
        lines.append("|------------|-------|----------------|")
        for lvl in ["High","Medium","Low"]:
            interp = {"High":"Factual — direct observation","Medium":"Probable — requires context","Low":"Speculative — needs verification"}[lvl]
            lines.append(f"| {lvl} | {s['by_reliability'][lvl]} | {interp} |")
        lines.append("")
        if s["corroborations"]:
            lines.append("### Corroborated Findings (Cross-Referenced)\n")
            lines.append("| Finding | Sources | Confidence |")
            lines.append("|---------|---------|------------|")
            for c in s["corroborations"][:10]:
                lines.append(f"| {c['finding']} | {', '.join(c['unique_sources'])} | {c['confidence_level']} ({c['combined_confidence']}) |")
            lines.append("")
        lines.append("### Source Breakdown\n")
        lines.append("| Source | Findings | Reliability |")
        lines.append("|--------|----------|-------------|")
        for src, st in sorted(s["source_breakdown"].items(), key=lambda x: -x[1]["count"]):
            lines.append(f"| {src} | {st['count']} | {st['reliability']} ({st['rank']}) |")
        lines.append("")
        lines.append(f"**Overall Assessment:** {s['overall_assessment']}")
        return "\n".join(lines)

# ── Audit Trail ──
class AuditTrail:
    """Structured log of decisions throughout the pipeline: Architect → Coder → Tool → Execute."""
    def __init__(self, session_id=""):
        self.session_id = session_id or datetime.now().strftime("%Y%m%d_%H%M%S")
        self.entries = []
        self.logfile = ""

    def log(self, stage, actor, action, details="", result="", level="info"):
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "session": self.session_id,
            "stage": stage,
            "actor": actor,
            "action": action,
            "details": details,
            "result": result,
            "level": level,
        }
        self.entries.append(entry)
        return entry

    def save(self, filepath=""):
        if not filepath:
            filepath = f"/tmp/sic_audit_{self.session_id}.json"
        self.logfile = filepath
        with open(filepath, "w") as f:
            json.dump({"session": self.session_id, "entries": self.entries}, f, indent=2)
        return filepath

    def summary(self):
        stages = {}
        for e in self.entries:
            stages.setdefault(e["stage"], {"calls": 0, "errors": 0})
            stages[e["stage"]]["calls"] += 1
            if e["level"] == "error": stages[e["stage"]]["errors"] += 1
        return {"session": self.session_id, "entries": len(self.entries), "stages": stages}

# ── CLI Entry Point ──
def cli():
    import argparse
    ap = argparse.ArgumentParser(description="SIC Analysis Engine — Confidence Scoring & Triangulation")
    ap.add_argument("--dir", help="Scan findings directory")
    ap.add_argument("--subject", default="", help="Report subject/name")
    ap.add_argument("--output", help="Save report to file")
    ap.add_argument("--json", action="store_true", help="Output raw JSON summary")
    args = ap.parse_args()
    
    engine = TriangulationEngine()
    if args.dir:
        if os.path.isfile(args.dir):
            with open(args.dir) as f: engine.add_raw(args.dir, f.read())
        else:
            engine.load_from_directory(args.dir)
    
    if args.json:
        print(json.dumps(engine.confidence_summary(), indent=2))
    else:
        report = engine.generate_report(args.subject)
        print(report)
        if args.output:
            with open(args.output, "w") as f: f.write(report)
            print(f"\nReport saved to {args.output}")

if __name__ == "__main__":
    cli()
