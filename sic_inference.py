#!/usr/bin/env python3
"""
SIC Inference Engine — Chain-of-Inference + Confidence Scoring + Audit Trail
---------------------------------------------------------------------------
Bridges HackerGPT-style features into the SIC bash pipeline.

Usage:
  python3 sic_inference.py --phase 1 --data '{"name":"John Doe"}' --output findings.json
  python3 sic_inference.py --report --inputdir vuln/ --subject "Target" --output report.md
"""

import json, os, sys, re, hashlib
from datetime import datetime, timezone

# ── Source Reliability Registry ──
SOURCE_RANKS = {
    "nmap":95,"nuclei":80,"testssl":85,"whatweb":70,"ffuf":60,
    "whois":75,"sherlock":65,"theharvester":70,"rapidapi":60,
    "github":85,"wikipedia":50,"duckduckgo":40,"dns":90,
    "phone_lookup":70,"leak_search":65,"social_media":55,
    "court_records":80,"property_records":85,"voter_records":75,
    "geolocation":70,"name_frequency":60,"ai_analysis":55,
    "google_dork":50,"haveibeenpwned":70,
}
SOURCE_LABELS = {
    95:"High",90:"High",85:"High",80:"High",75:"High",70:"Medium",
    65:"Medium",60:"Medium",55:"Medium",50:"Low",45:"Low",40:"Low",
}

def _src(name):
    n = name.lower()
    for k in sorted(SOURCE_RANKS, key=lambda x: -len(x)):
        if k in n: return {"name":k,"rank":SOURCE_RANKS[k],"label":SOURCE_LABELS.get(SOURCE_RANKS[k],"Medium")}
    return {"name":name,"rank":50,"label":"Medium"}

class Finding:
    def __init__(self, source, ftype, value, confidence=50, context="", phase=1):
        s = _src(source)
        self.source = source; self.ftype = ftype; self.value = value
        self.confidence = max(0, min(100, confidence if confidence else s["rank"]))
        self.source_rank = s["rank"]; self.source_label = s["label"]
        self.context = context; self.phase = phase
        self.timestamp = datetime.now(timezone.utc).isoformat()
        self.fingerprint = hashlib.md5(f"{ftype}:{value}".encode()).hexdigest()[:12]

    def to_dict(self):
        return {"fingerprint":self.fingerprint,"source":self.source,"source_rank":self.source_rank,
                "source_label":self.source_label,"type":self.ftype,"value":self.value,
                "confidence":self.confidence,"context":self.context,"phase":self.phase,"timestamp":self.timestamp}

class InferenceEngine:
    """Multi-phase inference with confidence accumulation."""
    def __init__(self):
        self.findings = []  # list of Finding
        self.phase_results = {}  # phase -> {findings, decisions}

    def add(self, source, ftype, value, confidence=50, context="", phase=1):
        f = Finding(source, ftype, value, confidence, context, phase)
        self.findings.append(f)
        return f

    def add_raw(self, source, text, phase=1):
        for line in text.strip().split("\n"):
            line = line.strip()
            if line and len(line) < 300:
                self.add(source, "raw", line, phase=phase)

    def find(self, ftype=None, value=None, min_confidence=0):
        results = []
        for f in self.findings:
            if ftype and f.ftype != ftype: continue
            if value and value.lower() not in f.value.lower(): continue
            if f.confidence < min_confidence: continue
            results.append(f)
        return results

    def corroborate(self, min_sources=2):
        """Find values that appear across multiple unique sources -> boost confidence."""
        groups = {}
        for f in self.findings:
            key = hashlib.md5(f"{f.ftype}:{f.value}".encode()).hexdigest()
            groups.setdefault(key, []).append(f)

        corr = []
        for key, matches in groups.items():
            sources = set(m.source for m in matches)
            if len(sources) >= min_sources:
                base = max(m.source_rank for m in matches)
                boosted = min(100, base + len(sources)*5)
                corr.append({"value":matches[0].value,"type":matches[0].ftype,
                             "sources":sorted(sources),"count":len(matches),
                             "confidence":boosted,"label":self._label(boosted)})
        return sorted(corr, key=lambda x: -x["confidence"])

    def _label(self, c):
        if c >= 85: return "High"
        if c >= 60: return "Medium"
        return "Low"

    def accumulate_confidence(self, finding_key, new_rank):
        """Update confidence for a finding based on new corroborating data."""
        for f in self.findings:
            key = hashlib.md5(f"{f.ftype}:{f.value}".encode()).hexdigest()
            if key == finding_key or f.value == finding_key:
                f.confidence = min(100, f.confidence + (new_rank // 10))
                return True
        return False

    def summary(self):
        hi = sum(1 for f in self.findings if f.confidence >= 85)
        med = sum(1 for f in self.findings if 60 <= f.confidence < 85)
        lo = sum(1 for f in self.findings if f.confidence < 60)
        corr = self.corroborate(2)
        return {"total":len(self.findings),"high":hi,"medium":med,"low":lo,
                "corroborations":corr,"by_phase":self._by_phase()}

    def _by_phase(self):
        p = {}
        for f in self.findings:
            p.setdefault(f.phase,{"count":0,"high":0,"med":0,"low":0})
            p[f.phase]["count"] += 1
            if f.confidence >= 85: p[f.phase]["high"] += 1
            elif f.confidence >= 60: p[f.phase]["med"] += 1
            else: p[f.phase]["low"] += 1
        return p

    def generate_report(self, subject="", details=None):
        s = self.summary()
        lines = [f"## Intelligence Report: {subject or 'Unknown'}\n"]
        lines.append("### Confidence by Phase\n")
        lines.append("| Phase | Findings | High | Medium | Low |")
        lines.append("|-------|----------|------|--------|-----|")
        for ph in sorted(s["by_phase"]):
            p = s["by_phase"][ph]
            lines.append(f"| {ph} | {p['count']} | {p['high']} | {p['med']} | {p['low']} |")
        lines.append(f"\n**Total:** {s['total']} findings\n")

        if details:
            lines.append("### Raw Details\n")
            for d in details:
                lines.append(f"- **{d.get('type','?')}:** {d.get('value','')}  ")
                lines.append(f"  *Source: {d.get('source','?')} — Confidence: {d.get('confidence',50)}*\n")
        return "\n".join(lines)

    def to_dict(self):
        return {"summary":self.summary(),"findings":[f.to_dict() for f in self.findings]}

# ── Audit Trail ──
class AuditTrail:
    def __init__(self, session=""):
        self.session = session or datetime.now().strftime("%Y%m%d_%H%M%S")
        self.entries = []
    def log(self, stage, actor, action, details="", result="", level="info"):
        e = {"timestamp":datetime.now(timezone.utc).isoformat(),"session":self.session,
             "stage":stage,"actor":actor,"action":action,"details":details,"result":result,"level":level}
        self.entries.append(e)
        print(f"[AUDIT][{stage}][{actor}] {action}: {details[:120]}...")
        return e
    def save(self, path=""):
        path = path or f"/tmp/sic_audit_{self.session}.json"
        with open(path,"w") as f: json.dump({"session":self.session,"entries":self.entries},f,indent=2)
        return path
    def errors(self): return [e for e in self.entries if e["level"]=="error"]

# ── CLI ──
def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", type=int, help="Inference phase number")
    ap.add_argument("--data", help="JSON data or @file.json")
    ap.add_argument("--output", help="Output file")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--inputdir", help="Input directory for reports")
    ap.add_argument("--subject", default="Target")
    ap.add_argument("--audit", help="Audit log file to load")
    args = ap.parse_args()

    engine = InferenceEngine()
    audit = AuditTrail()

    if args.phase and args.data:
        data = args.data
        if data.startswith("@"):
            with open(data[1:]) as f: data = f.read()
        try: data = json.loads(data) if isinstance(data,str) else data
        except: pass

        audit.log(f"phase{args.phase}","inference","phase_start",str(data)[:200])

        if args.phase == 1:
            # Phase 1: Parse and enrich raw input
            if isinstance(data, dict):
                for k,v in data.items():
                    if isinstance(v,str) and len(v) > 2:
                        engine.add(f"input.{k}","identity",v,phase=1)
            audit.log("phase1","inference","parsed_input",f"{sum(1 for _ in engine.findings)} findings")
        elif args.phase == 4:
            # Phase 4: Load directory and generate report
            if args.inputdir:
                for fn in sorted(os.listdir(args.inputdir)):
                    fp = os.path.join(args.inputdir,fn)
                    if os.path.isfile(fp) and os.path.getsize(fp) > 0:
                        try:
                            with open(fp,errors="replace") as f: txt = f.read()
                            engine.add_raw(fn,txt,phase=4)
                        except: pass
            corr = engine.corroborate(2)
            report = engine.generate_report(args.subject, [f.to_dict() for f in engine.findings])
            if args.output:
                with open(args.output,"w") as f: f.write(report)
                audit.log("phase4","inference","report_generated",args.output)
            print(report)
            if corr:
                print("\n### Corroborations Detected\n")
                for c in corr[:5]:
                    print(f"  {c['value']} — {c['label']} ({c['confidence']}) from {', '.join(c['sources'])}")

        if args.audit:
            audit.save(args.audit)

if __name__ == "__main__":
    main()
