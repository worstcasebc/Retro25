# SPDX-License-Identifier: GPL-3.0-or-later
"""Hilfen beim Portieren eines MiSTer-Cores auf Quartus Pro / Agilex 5.

Aufruf (aus dem Projektverzeichnis Retro25):
    python tools/port_core.py <core> scan
        Quelltext in cores/<core>/vendor durchsuchen und bekannte Probleme
        melden (ändert nichts): Cyclone-V-Primitive, Signale für 13386,
        VHDL-case ohne others, Paket-Import auf Dateiebene, relative .mif.
    python tools/port_core.py <core> fix13386 [--apply]
        "wire"/"output" ohne Typ, die in always beschrieben werden -> logic.
    python tools/port_core.py <core> fiximplicit [--apply]
        liest quartus/output_files/<core>.syn.rpt (nach quartus_syn) und
        behebt die Falle "implizite Netze" (16746/16749 -> 16788).
    python tools/port_core.py <core> report
        fasst die Warnungen des Syntheseberichts zusammen, die bei uns
        schon Fehler verursacht haben (16754, 16788, 1303x, 276009, 22556).

Ohne --apply wird nur angezeigt, was sich ändern würde. Mit --apply ändert
das Werkzeug die Kopien in cores/<core>/pro (legt sie aus vendor an, falls
nötig), schreibt deren .patch (tools/apply_patches.py --make) und stellt in
core.tcl den Pfad von {CORE}/vendor/... auf {CORE}/pro/... um.
Voraussetzung: Der Core steht in PAIRS von tools/apply_patches.py.

Warum? Quartus Standard (MiSTer) ist an vielen Stellen nachsichtiger als
Quartus Pro und meldet dort keinen Fehler; Pro bricht ab oder — schlimmer —
baut stillschweigend etwas anderes. Pro meldet je Datei oft nur den ersten
Fehler, daher lohnt das Suchen im ganzen Quelltext. Erfahrungen aus C64,
z486 und NES: docs/core-portieren.md.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply_patches  # noqa: E402  (read_src, make_patch, PAIRS)

NOTE_LOGIC = "   // Retro25: logic (in always beschrieben, Quartus Pro 13386)"
NOTE_ASSIGN = "// Retro25: vor der ersten Verwendung deklariert (Quartus Pro verwirft sonst die Zuweisung, 16746/16788)"
NOTE_MOVE = "// Retro25: Deklaration vor die erste Verwendung gezogen (Quartus Pro 16746)"
SV_EXT = (".v", ".sv")


# ----------------------------------------------------------------- Dateien
class Src:
    """Eine Quelldatei mit erhaltener Kodierung und Zeilenende."""

    def __init__(self, path: Path):
        self.path = path
        self.text, self.enc = apply_patches.read_src(path)
        self.eol = "\r\n" if "\r\n" in self.text else "\n"

    @property
    def lines(self) -> list[str]:
        return self.text.split(self.eol)

    def set_lines(self, lines: list[str]) -> None:
        self.text = self.eol.join(lines)

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(self.text.encode(self.enc))


class Core:
    def __init__(self, name: str):
        self.name = name
        self.dir = ROOT / "cores" / name
        self.vendor, self.pro = self.dir / "vendor", self.dir / "pro"
        if not self.vendor.is_dir():
            sys.exit(f"{self.vendor} fehlt (erst das fetch-Skript laufen lassen)")

    def current(self, rel: str) -> Path:
        """Arbeitsstand einer Datei: pro/-Kopie, sonst Original."""
        p = self.pro / rel
        return p if p.exists() else self.vendor / rel

    def sources(self, exts) -> list[str]:
        return sorted(p.relative_to(self.vendor).as_posix() for p in self.vendor.rglob("*")
                      if p.suffix.lower() in exts)

    def commit(self, changed: dict[str, Src]) -> None:
        """Kopien schreiben, Patches erzeugen, core.tcl umstellen."""
        if not any(pro == f"cores/{self.name}/pro" for pro, _ in apply_patches.PAIRS):
            sys.exit(f"cores/{self.name}/pro fehlt in PAIRS von tools/apply_patches.py")
        tcl = self.dir / "core.tcl"
        t = tcl.read_text(encoding="utf-8") if tcl.exists() else ""
        for rel, src in sorted(changed.items()):
            src.save(self.pro / rel)
            apply_patches.make_patch(str(self.pro / rel))
            t = t.replace("{CORE}/vendor/" + rel + "\n", "{CORE}/pro/" + rel + "\n")
        if tcl.exists():
            tcl.write_text(t, encoding="utf-8", newline="\n")
            missing = [r for r in changed if "{CORE}/pro/" + r not in t]
            if missing:
                print("Hinweis: in core.tcl nicht gefunden (von Hand eintragen):", ", ".join(missing))


# ------------------------------------------------------------------ 13386
KW = r"(?:assign|wire|logic|reg|parameter|localparam|input|output|inout|integer|int|bit|genvar|tri0|tri1|tri)"
CMT = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)


def proc_targets(text: str) -> set[str]:
    """Namen, die als Ziel einer prozeduralen Zuweisung vorkommen (grob)."""
    t = CMT.sub("", text)
    out = set()
    for stmt in re.split(r";|\bbegin\b|\bend\b|\bcase[xz]?\b|\bendcase\b|\belse\b", t):
        s = stmt.strip()
        if not s or re.match(rf"^{KW}\b", s):
            continue
        if re.match(r"^[^=]*?[^:]:[^:=]", s):          # case-Marke "2'b00 :"
            s = re.sub(r"^.*?:\s*(?=[A-Za-z_{])", "", s, flags=re.S)   # Marke auch nach Zeilenumbruch
        s = re.sub(r"^(if|for|while)\s*\(.*\)\s*", "", s, flags=re.S)
        s = re.sub(r"^(always(_comb|_ff|_latch)?|initial)\b(\s*@\s*(\*|\([^)]*\)))?\s*", "", s)
        m = re.match(r"^\{([^}]*)\}\s*<?=(?!=)", s)
        if m:
            out |= {n.group(1) for part in m.group(1).split(",")
                    if (n := re.match(r"\s*([A-Za-z_]\w*)", part))}
            continue
        m = re.match(r"^([A-Za-z_]\w*)\s*(\[[^\]]*\]\s*)*<?=(?!=)", s)
        if m:
            out.add(m.group(1))
    return out


def names_in(decl: str) -> set[str]:
    return set(re.findall(r"[A-Za-z_]\w*", re.sub(r"\[[^\]]*\]", "", decl)))


WIRE_DECL = re.compile(r"^\s*wire\b([^;=]*);")
OUT_DECL = re.compile(r"^\s*output\b(?!\s*(reg|logic|wire)\b)([^;=]*?)\s*,?\s*$")


def fix13386_text(src: Src) -> int:
    """wire/output ohne Typ -> logic, wenn prozedural beschrieben. Anzahl Zeilen.
    Die Zuweisungsziele werden je Modul gesammelt (gleiche Namen in anderen
    Modulen derselben Datei zählen nicht)."""
    lines = src.lines
    want_at, want = [], set()
    starts = [i for i, l in enumerate(lines) if re.match(r"^\s*module\b", l)] or [0]
    for k, s in enumerate(starts):
        e = starts[k + 1] if k + 1 < len(starts) else len(lines)
        tg = proc_targets("\n".join(lines[s:e]))
        want_at += [tg] * (e - len(want_at)) if k else [tg] * e
    out, n = [], 0
    for i, ln in enumerate(lines):
        want = want_at[i] if i < len(want_at) else set()
        code = ln.split("//")[0]
        m = WIRE_DECL.match(code)
        if m and names_in(m.group(1)) & want:
            ln = re.sub(r"^(\s*)wire\b", r"\1logic", ln, count=1) + NOTE_LOGIC
            n += 1
        else:
            m = OUT_DECL.match(code)
            if m and names_in(m.group(2)) & want:
                ln = re.sub(r"^(\s*)output\b", r"\1output logic", ln, count=1)
                n += 1
        out.append(ln)
    src.set_lines(out)
    return n


# ------------------------------------------------------- implizite Netze
def module_bounds(lines: list[str], i: int) -> tuple[int, int, int]:
    """(Zeile "module", Zeile ");" der Portliste, Zeile "endmodule") um Zeile i."""
    ms = max(j for j in range(i + 1) if re.match(r"^\s*module\b", lines[j]))
    me = next(j for j in range(i, len(lines)) if re.match(r"^\s*endmodule\b", lines[j]))
    hdr = next(j for j in range(ms, me) if re.match(r"^\s*\);", lines[j]))
    return ms, hdr, me


def fix_implicit_text(src: Src, uses: list[tuple[int, str]], decl_lines: set[int]) -> list[str]:
    """uses: (Zeile der ersten Verwendung, Name) aus 16749/16746.
    decl_lines: Zeilen mit "already implicitly declared" (Deklaration ohne =).
    Ergebnis: Liste der Änderungen (Text)."""
    L = src.lines
    log, inserts, moved, done = [], {}, set(), set()
    for line, name in sorted(set(uses)):
        u = line - 1
        try:
            ms, hdr, me = module_bounds(L, u)
        except (ValueError, StopIteration):
            continue
        if (ms, name) in done:
            continue
        rx = re.compile(rf"^(\s*)wire(\s+signed)?\s*(\[[^\]]*\])?\s*{name}\s*=(?!=)")
        for i in range(u + 1, me):
            m = rx.match(L[i].split("//")[0])
            if m:
                rng = (m.group(2) or "") + (" " + m.group(3) if m.group(3) else "")
                L[i] = rx.sub(lambda mm: f"{mm.group(1)}assign {name} =", L[i], count=1)
                inserts.setdefault(hdr, []).extend([NOTE_ASSIGN, f"wire{rng} {name};"])
                done.add((ms, name))
                log.append(f"{name}: wire{rng} nach oben, Zeile {i + 1} -> assign")
                break
    decl = re.compile(r"^\s*(wire|reg|logic)\b[^;]*;\s*(//.*)?$")
    for n in sorted(decl_lines):
        i = n - 1
        code = L[i].split("//")[0]
        if not decl.match(L[i]) or (code.lstrip().startswith("wire") and "=" in code):
            continue                      # Fall mit "=" erledigt der Teil oben
        _, hdr, _ = module_bounds(L, i)
        inserts.setdefault(hdr, []).extend([NOTE_MOVE, L[i].strip()])
        moved.add(i)
        log.append(f"Zeile {n} nach oben: {L[i].strip()[:60]}")
    new = []
    for j, l in enumerate(L):
        new.append("// Retro25: Deklaration nach oben gezogen (16746): " + l.strip() if j in moved else l)
        if j in inserts:
            new += inserts[j]
    src.set_lines(new)
    return log


def parse_report(core: Core):
    rpt = core.dir / "quartus" / "output_files" / f"{core.name}.syn.rpt"
    if not rpt.exists():
        sys.exit(f"{rpt} fehlt (erst quartus_syn laufen lassen)")
    uses, decls = {}, {}
    pre = rf"File: Q:/cores/{core.name}/(?:pro|vendor)/(\S+) Line: (\d+)"
    for ln in rpt.read_text(encoding="latin-1").splitlines():
        m = re.search(r"\((16746|16749)\).*?identifier \"?(\w+)\"? is used before its declaration.*" + pre, ln)
        if m:
            uses.setdefault(m.group(3), []).append((int(m.group(4)), m.group(2)))
            continue
        m = re.search(r"\(16746\).*?: (\w+) is already implicitly declared on line (\d+).*" + pre, ln)
        if m:
            uses.setdefault(m.group(3), []).append((int(m.group(2)), m.group(1)))
            decls.setdefault(m.group(3), set()).add(int(m.group(4)))
    return rpt, uses, decls


# ------------------------------------------------------------------- scan
PRIMS = re.compile(r"\b(altsyncram|altddio_out|altddio_in|altera_pll|altpll|altdpram|cyclonev_\w+|"
                   r"intended_device_family\s*\(?\s*\"Cyclone)", re.I)


def vhdl_case_without_others(text: str) -> list[int]:
    """Zeilennummern des letzten when-Zweigs von case-Blöcken ohne others."""
    stack, res = [], []
    for i, ln in enumerate(text.splitlines()):
        code = ln.split("--")[0].lower()
        if re.search(r"\bend\s+case\b", code):
            c = stack.pop() if stack else None
            if c and not c["others"] and c["last"] is not None:
                res.append(c["last"] + 1)
        elif re.search(r"\bcase\b.*\bis\b", code):
            stack.append({"others": False, "last": None})
        elif stack and re.match(r"^\s*when\b", code):
            stack[-1]["others"] |= bool(re.match(r"^\s*when\s+others\b", code))
            stack[-1]["last"] = i
    return res


def cmd_scan(core: Core) -> None:
    print(f"== {core.name}: Quelltext unter {core.vendor.relative_to(ROOT)}")
    for rel in core.sources(SV_EXT + (".vhd", ".vhdl")):
        src = Src(core.vendor / rel)   # Original, nicht die pro-Kopie
        found = []
        for i, ln in enumerate(src.text.splitlines(), 1):
            if PRIMS.search(ln.split("//")[0].split("--")[0]):
                found.append(f"  {i}: Cyclone-Primitive: {ln.strip()[:70]}")
            m = re.search(r"\"(rtl/[^\"]+\.(mif|hex|mem))\"", ln)
            if m:
                found.append(f"  {i}: Pfad relativ zum MiSTer-Projekt: {m.group(1)}")
            if re.match(r"^\s*import\s+\w+::\*\s*;", ln) and not ln.startswith(" ") and i < 30:
                found.append(f"  {i}: Paket-Import auf Dateiebene (gilt bei Quartus Pro nur in dieser Datei)")
        if rel.endswith(SV_EXT):
            tmp = Src(core.vendor / rel)
            n = fix13386_text(tmp)
            if n:
                found.append(f"  13386: {n} Deklaration(en) wire/output -> logic (fix13386)")
        else:
            for n in vhdl_case_without_others(src.text):
                found.append(f"  {n}: VHDL-case ohne others (std_logic_vector? dann letzten Zweig -> others)")
        if found:
            print(rel)
            print("\n".join(found))


def cmd_fix13386(core: Core, apply: bool) -> None:
    changed = {}
    for rel in core.sources(SV_EXT):
        src = Src(core.current(rel))
        n = fix13386_text(src)
        if n:
            print(f"{rel}: {n} Zeile(n)")
            changed[rel] = src
    if apply and changed:
        core.commit(changed)


def cmd_fiximplicit(core: Core, apply: bool) -> None:
    rpt, uses, decls = parse_report(core)
    changed = {}
    for rel in sorted(set(uses) | set(decls)):
        src = Src(core.current(rel))
        log = fix_implicit_text(src, uses.get(rel, []), decls.get(rel, set()))
        if log:
            print(f"{rel}: {len(log)} Änderung(en)")
            for x in log:
                print("  " + x)
            changed[rel] = src
    if apply and changed:
        core.commit(changed)


def cmd_report(core: Core) -> None:
    rpt = core.dir / "quartus" / "output_files" / f"{core.name}.syn.rpt"
    if not rpt.exists():
        sys.exit(f"{rpt} fehlt")
    text = rpt.read_text(encoding="latin-1")
    why = {"16754": "Register mit Startwert in always (Pro setzt es jeden Takt zurück)",
           "16788": "Netz ohne Treiber (oft implizite Netze -> fiximplicit)",
           "16746": "implizites Netz, Attribute/Startwert verworfen (-> fiximplicit)",
           "13034": "Tri-State falsch aufgelöst", "13035": "Tri-State falsch aufgelöst",
           "13028": "Tri-State falsch aufgelöst",
           "276009": "RAM nicht inferiert (Lese-/Schreibverhalten) -> no_rw_check",
           "22556": "TDP-RAM mit zwei Takten (Agilex 5 kann das nicht)"}
    for code, text_why in why.items():
        hits = [ln for ln in text.splitlines() if f"({code})" in ln and f"cores/{core.name}/" in ln]
        if hits:
            print(f"{code} ({len(hits)}x): {text_why}")
            for h in hits[:8]:
                print("   " + re.sub(r" File: .*", "", h).strip()[:110])


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    core, cmd = Core(args[0]), args[1]
    apply = "--apply" in sys.argv
    {"scan": lambda: cmd_scan(core),
     "fix13386": lambda: cmd_fix13386(core, apply),
     "fiximplicit": lambda: cmd_fiximplicit(core, apply),
     "report": lambda: cmd_report(core)}.get(cmd, lambda: sys.exit(__doc__))()
    return 0


if __name__ == "__main__":
    sys.exit(main())
