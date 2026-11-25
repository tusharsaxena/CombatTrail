#!/usr/bin/env python3
"""tools/seeds/seeds.py — re-validate Combat Trail's seed lists against one client's wago.tools build.

WHAT THIS IS
    The contract `/dev-copilot:validate-seeds CombatTrail <flavor>` runs (docs/validate-seeds.md). It
    supersedes DPS Race's contract (DPS Race is retired and archived; its Hearthstones list and its
    dummy catalog live here now). Combat Trail ships these seed lists:

    defaults/Hearthstones.lua   NS.HEARTHSTONE_SPELLS, every hearthstone variant's spell id (Race mode,
                                Retail). DERIVED: the file's header states the four rules it was built
                                by, and `derive` runs exactly those rules (derive_hearthstones). Flavor
                                `retail` only.
    defaults/IgnoreSeeds.lua    NS.IgnoreSeeds.<Client>.<lane>, each lane's ignored auto-repeat spells.
                                CURATED, not derived: it takes no candidates. Every shipped id is
                                checked on the flavor's own build (the `unnamed` and `renamed` flags),
                                against the name the file's header gives it.
    defaults/Dummies.lua        NS.DummySeeds, the training-dummy catalog. MEASURED: a row is added from
                                a capture in game and never guessed, so it takes no candidates that can
                                be accepted.
                                  Retail: not checkable. The client's Creature DB2 holds none of the
                                  catalog's ids (a dummy's name reaches the client from the server), so
                                  this tool reads no Creature table (docs/validate-seeds.md, Notes).
                                  Forever: EMPTY BY DECISION. The ForeverDB evidence step lists every
                                  ForeverDB creature whose name says "dummy" as a candidate `dummies:<id>`
                                  for information only; `reject` is the only ruling it takes.

    Candidates (ruled accept or reject):
        hearthstones:<id>   ids the build's rules derive that the list does not ship (retail)
        dummies:<id>        ForeverDB creatures named as dummies (forever; reject only)
    Flags (ruled keep or remove), over every shipped id:
        shipped:unnamed:<list>:<id>   the build's SpellName has no row for it
        shipped:renamed:<list>:<id>   its name on the build disagrees with the file's name for it
        shipped:unfit:hearthstones:<id>  it is named but the four rules no longer derive it

    A ruling is keyed by list and id, never by build, and holds until the thing it ruled on stops
    being proposed. Each flavor keeps its own file, tools/seeds/<flavor>_rulings.json.

HOW THE FOUR RULES READ (defaults/Hearthstones.lua's header)
    1. every spell with a SpellCategories row whose ChargeCategory is 2309 (any DifficultyID);
    2. plus every spell with a SpellEffect row of Effect 252 (teleport) and ImplicitTarget 9 (the
       bind point) in either target slot. The header adds "that a toy or an item casts", and rule 4
       then removes by id "the teleports home no item casts or that are test data": the 2026-10-28
       list was therefore every bind-point teleport less rule 4's ids. That reading is the one that
       reproduces the shipped list (three shipped ids, 191329, 431644 and 1286909, have no ItemEffect
       row of their own), so it is the one coded here; whether an item casts the spell, directly or
       through a spell whose EffectTriggerSpell it is, is reported on every candidate as a note for
       the ruling instead (ItemEffect, ItemXItemEffect, Toy);
    3. plus 222695 and 171253, by id;
    4. minus EXCLUDED, by id.
    A sentinel gate (SENTINELS) stops the run when the rules come up thin.

FOREVERDB (flavor `forever` only; GPL-3.0 data, standard clients-§10)
    Read only through dev-copilot's helper, `foreverdb.py fetch --tag <tag> --date <date>`, which
    prints the cache folder holding foreverdb.json and SOURCES.json. Nothing of it is copied into the
    repo: the bundle keeps the tag, the commit, each file's sha256 and per-id verdicts (an id and the
    one field compared, its name), never a row. A replay re-fetches the pinned tag, which is
    immutable.

THE STEPS
    python3 tools/seeds/seeds.py status --flavor retail
    python3 tools/seeds/seeds.py status --flavor forever --foreverdb <tag>
    python3 tools/seeds/seeds.py derive --flavor retail --bundle docs/seed-research/<date>-retail --date <date> [--build V] [--replay]
    python3 tools/seeds/seeds.py derive --flavor forever --bundle docs/seed-research/<date>-forever --date <date> \\
        --foreverdb <tag> --foreverdb-script <root>/scripts/foreverdb.py [--foreverdb-install DIR] [--build V] [--replay]
    python3 tools/seeds/seeds.py check  --bundle <bundle>
    python3 tools/seeds/seeds.py rule   --tsv <file> --bundle <bundle>
    python3 tools/seeds/seeds.py report --bundle <bundle> --date <date>
    python3 tools/seeds/seeds.py apply  --bundle <bundle> --date <date>

    `derive` pins one build (`--build`, else the flavor's newest live, non-background-download build
    from the builds API), fetches every table into the git-ignored tools/seeds/.cache/ (streamed,
    never read whole), freezes them gzipped into the bundle's raw/, and writes SOURCES.md, DIFF.md
    and candidates.json. `--replay` reads only the bundle's raw/ for the DB2 tables (the ForeverDB
    step still goes through the helper, whose cache answers a pinned tag offline). `rule` is the
    only writer of the rulings files. `check` exits 1 while anything is unruled. `report` writes
    RULINGS.md. `apply` refuses while anything is unruled, is idempotent, and keeps each file's line
    endings and layout. The date is always an argument; nothing here reads the clock.

    Ported from DPS Race's tools/seeds/seeds.py (2026-11-15), which copied Aura Master's patterns;
    nothing is imported across repos. Whether a shared helper should carry the build pin, the cache,
    the bundle and the rulings is LibKa0s#91.

Python 3.8+ and its standard library only.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
RESEARCH = REPO / "docs" / "seed-research"
CACHE_DIR = HERE / ".cache"
HEARTH_FILE = REPO / "defaults" / "Hearthstones.lua"
IGNORE_FILE = REPO / "defaults" / "IgnoreSeeds.lua"

BUILDS_URL = "https://wago.tools/api/builds"
CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
# wago.tools answers HTTP 403 to urllib's default User-Agent; this says who is asking.
USER_AGENT = "CombatTrail-seed-check"
DOWNLOAD_CHUNK = 1 << 20  # SpellEffect is ~57 MB: always streamed, never read into one string

# The tables each flavor reads. The fetch list IS the list SOURCES.md records, so a bundle never
# claims a table it did not read.
RETAIL_TABLES = (
    ("SpellCategories", "ChargeCategory: hearthstones rule 1, the hearthstone charge category 2309"),
    ("SpellEffect", "Effect 252 + ImplicitTarget 9: hearthstones rule 2; EffectTriggerSpell: the item-cast note"),
    ("SpellName", "every shipped hearthstone's and ignore seed's name, for the unnamed and renamed flags"),
    ("ItemEffect", "the spell an item effect casts: the item-cast note on a rule 2 candidate"),
    ("ItemXItemEffect", "item effect -> item: which item casts it"),
    ("Toy", "item -> toy: whether the item that casts it is a toy"),
)
FOREVER_TABLES = (
    ("SpellName", "every shipped ignore seed's name, for the unnamed and renamed flags"),
)

# The client a flavor validates, its own wago product (clients-§10), what it reads and checks.
FLAVORS = {
    "retail": {"product": "wow", "title": "Retail", "client": "Retail", "tables": RETAIL_TABLES,
               "lists": ("hearthstones", "ignore"), "foreverdb": False},
    "forever": {"product": "wowf", "title": "WoW Forever", "client": "Forever", "tables": FOREVER_TABLES,
                "lists": ("ignore", "dummies"), "foreverdb": True},
}

HEARTH_CHARGE_CATEGORY = "2309"
TELEPORT_EFFECT = "252"
BIND_POINT_TARGET = "9"
FIXED = {222695: "Dalaran Hearthstone: a cooldown of its own, a fixed destination (rule 3)",
         171253: "Garrison Hearthstone: a cooldown of its own, a fixed destination (rule 3)"}
EXCLUDED = {
    556: "Astral Recall, a class spell a player can add (rule 4)",
    1: "Word of Recall (OLD), test data (rule 4)",
    3: "Word of Mass Recall (OLD), test data (rule 4)",
    70195: "[PH] Portable Hole, a placeholder (rule 4)",
    307896: "Hearthstone - Ethereal - TEST, test data (rule 4)",
    1223998: "[DNT] Force Hearthstone, test data (rule 4)",
    49493: "Mole Machine Port to Hearth: no item casts it, not on the hearthstone cooldown (rule 4)",
    188816: "Teleport: no item casts it, not on the hearthstone cooldown (rule 4)",
}
# Ids the game, not this tool's output, says must be derived: the Hearthstone itself (rule 1) and
# rule 3's two. A run that misses one stops rather than proposing to remove half the list.
SENTINELS = {8690: "Hearthstone", 222695: "Dalaran Hearthstone", 171253: "Garrison Hearthstone"}

# A ForeverDB creature is listed as a dummy candidate when its name holds this word.
DUMMY_NAME = re.compile(r"\bdummy\b", re.I)

LISTS = ("hearthstones", "ignore", "dummies")
CANDIDATE_RULINGS = {"hearthstones": ("accept", "reject"),
                     # defaults/Dummies.lua: Forever is EMPTY BY DECISION and a row is only measured.
                     "dummies": ("reject",)}
FLAG_RULINGS = ("keep", "remove")
FLAG_KINDS = {"hearthstones": ("unnamed", "renamed", "unfit"), "ignore": ("unnamed", "renamed"),
              "dummies": ()}
KEY = re.compile(r"^(?:shipped:(?P<kind>[a-z-]+):)?(?P<list>[a-z]+):(?P<id>\d+)$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TAG_RE = re.compile(r"^v\d{4}\.\d{2}\.\d{2}\.\d+$")

HEARTH_TABLE_OPEN = re.compile(r"^NS\.HEARTHSTONE_SPELLS\s*=\s*\{\s*$")
HEARTH_ROW = re.compile(r"^\s+(\d+),\s*--\s*(.*?)\s*$")
IGNORE_TABLE_OPEN = re.compile(r"^NS\.IgnoreSeeds\s*=\s*\{\s*$")
IGNORE_CLIENT = re.compile(r"^\s+(Retail|Forever)\s*=\s*\{\s*$")
IGNORE_LANE = re.compile(r"^(\s+)(player|pet)(\s*=\s*)\{([\d,\s]*)\}(,?)\s*$")
IGNORE_HEADER = re.compile(r"^--\s+(player|pet)\s+(.*)$")
NAMED_ID = re.compile(r"^\s*(.+?)\s+(\d+)\b")


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Files: CRLF in this repo (.gitattributes `* text=auto eol=crlf`), whatever Python's default is
# ---------------------------------------------------------------------------

def write_repo_text(path: Path, text: str) -> None:
    """Write a tracked text file with CRLF terminators, as bytes (tests/_kit/test_eol.lua checks)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))


def write_json(path: Path, doc) -> None:
    write_repo_text(path, json.dumps(doc, indent=1, sort_keys=True, ensure_ascii=False) + "\n")


def split_lines(text: str):
    """`(lines, newline)`: the file's lines without terminators, and the terminator it uses."""
    newline = "\r\n" if "\r\n" in text else "\n"
    return text.replace("\r\n", "\n").split("\n"), newline


# ---------------------------------------------------------------------------
# wago.tools
# ---------------------------------------------------------------------------

def http_get(url: str, accept: str = "*/*"):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    try:
        return urllib.request.urlopen(req, timeout=300)
    except urllib.error.HTTPError as err:  # 400: no such table on this build; 403: the User-Agent
        raise SystemExit("HTTP %s fetching %s: %s" % (err.code, url, err.reason))
    except urllib.error.URLError as err:
        raise SystemExit("Could not reach %s: %s (a new run needs network access)" % (url, err.reason))


def newest_live(builds: list) -> str:
    """The first (newest) build that is not a background download, from one product's list."""
    for entry in builds or ():
        if not entry.get("is_bgdl"):
            return entry["version"]
    raise SystemExit("The builds API listed no live build; pass --build.")


def live_build(product: str) -> str:
    """The newest live build of `product` from the builds API (newest first per product)."""
    data = json.load(http_get(BUILDS_URL, accept="application/json"))
    return newest_live(data.get(product))


def fetch_table(table: str, build: str, cache_dir: Path) -> Path:
    """One table's CSV for `build`, from the cache or streamed into it (renamed only when whole)."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    dest = cache_dir / ("%s-%s.csv" % (table, build))
    if dest.exists():
        log("  %-16s cached (%.1f MB)" % (table, dest.stat().st_size / 1e6))
        return dest
    url = CSV_URL.format(table=table, build=build)
    tmp = dest.with_suffix(".csv.part")
    log("  %-16s fetching %s" % (table, url))
    with http_get(url, accept="text/csv") as response, tmp.open("wb") as handle:
        shutil.copyfileobj(response, handle, DOWNLOAD_CHUNK)
    tmp.replace(dest)
    return dest


def freeze_tables(bundle: Path, build: str, cache_dir: Path, replay: bool, tables=RETAIL_TABLES) -> dict:
    """`{table: raw member}`: every one of `tables` in the bundle's raw/, gzipped from the cache
    unless `replay`, where the bundle must already hold each one."""
    raw = bundle / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    out = {}
    for table, _why in tables:
        member = raw / ("%s.csv.gz" % table)
        if replay:
            if not member.exists():
                raise SystemExit("--replay: %s is missing raw/%s.csv.gz; a bundle that cannot hand "
                                 "back every table it read cannot reproduce its numbers." % (bundle, table))
        else:
            source = fetch_table(table, build, cache_dir)
            # mtime=0 and no file name in the header: the same CSV always freezes to the same bytes.
            with source.open("rb") as src, member.open("wb") as raw_out, \
                    gzip.GzipFile(filename="", mode="wb", compresslevel=9, fileobj=raw_out, mtime=0) as dst:
                shutil.copyfileobj(src, dst, DOWNLOAD_CHUNK)
        out[table] = member
    return out


def iter_csv(path: Path):
    """Each row as a dict, one at a time; a `.gz` member is decompressed on the fly. Columns are
    addressed by header name, never by position (clients-§10)."""
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            yield row


def _int(value) -> int:
    try:
        return int(value or 0)
    except ValueError:
        return 0


# ---------------------------------------------------------------------------
# ForeverDB, through dev-copilot's helper (never read any other way)
# ---------------------------------------------------------------------------

def foreverdb_fetch(script: Path, tag: str, date: str, install=None) -> Path:
    """The helper's cache folder for `tag`: `foreverdb.py fetch` prints it as its last line."""
    if not TAG_RE.match(tag or ""):
        raise SystemExit("--foreverdb %r is not a vYYYY.MM.DD.N tag." % tag)
    if not script or not Path(script).is_file():
        raise SystemExit("--foreverdb-script %s: pass dev-copilot's scripts/foreverdb.py." % script)
    cmd = [sys.executable, str(script), "fetch", "--tag", tag, "--date", date]
    if install:
        cmd += ["--from-install", str(install)]
    log("  ForeverDB %s via %s" % (tag, script))
    done = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if done.returncode != 0:
        raise SystemExit("foreverdb.py fetch refused (%d): %s" % (done.returncode, done.stderr.strip()))
    lines = [line for line in done.stdout.splitlines() if line.strip()]
    if not lines:
        raise SystemExit("foreverdb.py fetch printed no cache folder.")
    return Path(lines[-1].strip())


def script_commit(script) -> str:
    """The git commit of the checkout `script` sits in, or "" (an installed plugin copy)."""
    try:
        done = subprocess.run(["git", "-C", str(Path(script).resolve().parent), "rev-parse", "HEAD"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True)
    except OSError:
        return ""
    return done.stdout.strip() if done.returncode == 0 else ""


def load_foreverdb(folder: Path) -> dict:
    """`{"db": the ForeverDB global, "sources": SOURCES.json}` from the helper's cache folder."""
    try:
        db = json.loads((folder / "foreverdb.json").read_text(encoding="utf-8"))
        sources = json.loads((folder / "SOURCES.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        raise SystemExit("ForeverDB cache %s is unreadable: %s" % (folder, err))
    return {"db": db, "sources": sources}


def derive_dummies(db: dict) -> list:
    """`[{id, name, notes}]`: every ForeverDB creature whose name holds the word "dummy", with
    whether it has a spawn recorded. Information only (defaults/Dummies.lua: EMPTY BY DECISION)."""
    npcs, spots = db.get("npc"), db.get("spm") if isinstance(db.get("spm"), dict) else {}
    if not isinstance(npcs, dict):
        raise SystemExit("ForeverDB has no npc table keyed by id; the reshaped format needs a tool fix.")
    out = []
    for key, row in npcs.items():
        name = row[0] if isinstance(row, list) and row and isinstance(row[0], str) else None
        if not name or not DUMMY_NAME.search(name) or not str(key).isdigit():
            continue
        maps = spots.get("c%s" % key)
        where = ("spawn recorded on %d map(s)" % len(maps)) if isinstance(maps, dict) and maps \
            else "no spawn recorded"
        out.append({"id": int(key), "name": name, "notes": ["ForeverDB creature name match", where]})
    return sorted(out, key=lambda r: r["id"])


# ---------------------------------------------------------------------------
# The build's facts
# ---------------------------------------------------------------------------

class Facts:
    """What the rules and the flags read off one build's tables. A flavor that reads only SpellName
    (forever) leaves the hearthstone facts empty."""

    def __init__(self, tables: dict):
        self.spell_names = {_int(r["ID"]): r["Name_lang"] for r in iter_csv(tables["SpellName"])}
        self.charge, self.teleports, self.triggered_by, self.cast_by = set(), set(), {}, {}
        if "SpellCategories" not in tables:
            return
        self.charge = {_int(r["SpellID"]) for r in iter_csv(tables["SpellCategories"])
                       if r["ChargeCategory"] == HEARTH_CHARGE_CATEGORY}
        for r in iter_csv(tables["SpellEffect"]):
            spell = _int(r["SpellID"])
            if r["Effect"] == TELEPORT_EFFECT and BIND_POINT_TARGET in (r["ImplicitTarget_0"], r["ImplicitTarget_1"]):
                self.teleports.add(spell)
            trigger = _int(r["EffectTriggerSpell"])
            if trigger:
                self.triggered_by.setdefault(trigger, set()).add(spell)
        effect_spell = {_int(r["ID"]): _int(r["SpellID"]) for r in iter_csv(tables["ItemEffect"])}
        toys = {_int(r["ItemID"]) for r in iter_csv(tables["Toy"])}
        for r in iter_csv(tables["ItemXItemEffect"]):  # spell -> {(item, is_toy)}
            spell = effect_spell.get(_int(r["ItemEffectID"]))
            if spell:
                item = _int(r["ItemID"])
                self.cast_by.setdefault(spell, set()).add((item, item in toys))

    def item_note(self, spell: int) -> str:
        """Who casts `spell`: a toy, an item, or a spell an item casts (one EffectTriggerSpell hop)."""
        direct = sorted(self.cast_by.get(spell, ()))
        if direct:
            return "cast by " + ", ".join("%s %d" % ("toy" if toy else "item", item) for item, toy in direct[:4])
        parents = sorted(p for p in self.triggered_by.get(spell, ()) if p in self.cast_by)
        if parents:
            return "triggered by %s, which an item casts" % ", ".join(str(p) for p in parents[:4])
        return "no item casts it"


def derive_hearthstones(facts: Facts) -> dict:
    """`{id: [rules]}`: the four rules of defaults/Hearthstones.lua's header, as the docstring reads
    them. Raises SystemExit when a sentinel is not derived."""
    out = {}
    for spell in facts.charge:
        out.setdefault(spell, []).append("rule 1: ChargeCategory 2309")
    for spell in facts.teleports:
        out.setdefault(spell, []).append("rule 2: Effect 252, ImplicitTarget 9")
    for spell in FIXED:
        out.setdefault(spell, []).append("rule 3: by id")
    for spell in EXCLUDED:
        out.pop(spell, None)
    missing = ["%d %s" % (s, n) for s, n in sorted(SENTINELS.items()) if s not in out or s not in facts.spell_names]
    if missing:
        raise SystemExit("Hearthstone sentinel gate FAILED: %s not derived. Fix the rules before ruling."
                         % ", ".join(missing))
    return out


# ---------------------------------------------------------------------------
# The seed files
# ---------------------------------------------------------------------------

def read_hearthstones(path: Path) -> list:
    """`[{id, name}]`, in file order, from the NS.HEARTHSTONE_SPELLS table."""
    lines, _nl = split_lines(path.read_bytes().decode("utf-8"))
    rows, inside = [], False
    for line in lines:
        if HEARTH_TABLE_OPEN.match(line):
            inside = True
            continue
        if inside:
            if line.strip() == "}":
                return rows
            match = HEARTH_ROW.match(line)
            if not match:
                raise SystemExit("%s: %r is not an `<id>, -- <name>` row." % (path, line))
            rows.append({"id": int(match.group(1)), "name": match.group(2)})
    raise SystemExit("%s: no closed NS.HEARTHSTONE_SPELLS table." % path)


def _ignore_block(lines: list, path: Path):
    """`(start, end)`: the line indexes of `NS.IgnoreSeeds = {` and its closing `}`."""
    start = next((i for i, line in enumerate(lines) if IGNORE_TABLE_OPEN.match(line)), None)
    if start is None:
        raise SystemExit("%s: no NS.IgnoreSeeds table." % path)
    end = next((i for i in range(start + 1, len(lines)) if lines[i] == "}"), None)
    if end is None:
        raise SystemExit("%s: NS.IgnoreSeeds is not closed by a `}` line." % path)
    return start, end


def _ids(text: str) -> list:
    return [int(part) for part in text.replace(" ", "").split(",") if part]


def read_ignore(path: Path, client: str) -> dict:
    """`{"lanes": {lane: [ids]}, "names": {id: header name}}` for one client of NS.IgnoreSeeds. The
    names come from the header's `-- player  Auto Attack 6603, ...` lines (the file's own labels)."""
    lines, _nl = split_lines(path.read_bytes().decode("utf-8"))
    names = {}
    for line in lines:
        header = IGNORE_HEADER.match(line)
        if header:
            for part in header.group(2).split(","):
                named = NAMED_ID.match(part)
                if named:
                    names.setdefault(int(named.group(2)), named.group(1))
    start, end = _ignore_block(lines, path)
    lanes, current = {}, None
    for line in lines[start + 1:end]:
        opened = IGNORE_CLIENT.match(line)
        if opened:
            current = opened.group(1)
            continue
        lane = IGNORE_LANE.match(line)
        if lane and current == client:
            lanes[lane.group(2)] = _ids(lane.group(4))
    if not lanes:
        raise SystemExit("%s: NS.IgnoreSeeds has no %s lanes." % (path, client))
    return {"lanes": lanes, "names": names}


def ignore_rows(seed: dict) -> list:
    """`[{id, name, lanes}]`: each distinct id of one client's ignore seeds, in first-seen order."""
    rows, seen = [], {}
    for lane in ("player", "pet"):
        for spell in seed["lanes"].get(lane, ()):
            if spell not in seen:
                seen[spell] = {"id": spell, "name": seed["names"].get(spell, ""), "lanes": []}
                rows.append(seen[spell])
            seen[spell]["lanes"].append(lane)
    return rows


# ---------------------------------------------------------------------------
# Candidates and flags
# ---------------------------------------------------------------------------

def _flag(kind: str, lst: str, row: dict, build_name: str) -> dict:
    return {"key": "shipped:%s:%s:%d" % (kind, lst, row["id"]), "kind": kind, "list": lst,
            "id": row["id"], "name": build_name or "", "comment": row["name"]}


def name_flags(facts: Facts, lst: str, shipped: list) -> list:
    """`unnamed` and `renamed` over `shipped` ([{id, name}]); a row the file names nothing (an
    empty name) is checked for existence only."""
    flags = []
    for row in shipped:
        name = facts.spell_names.get(row["id"])
        if not name:
            flags.append(_flag("unnamed", lst, row, ""))
        elif row["name"] and name.lower() != row["name"].lower():
            flags.append(_flag("renamed", lst, row, name))
    return flags


def hearth_findings(facts: Facts, derived: dict, shipped: list):
    """`(candidates, flags)` for the hearthstone list."""
    ids = {row["id"] for row in shipped}
    candidates = [{"key": "hearthstones:%d" % s, "list": "hearthstones", "id": s,
                   "name": facts.spell_names.get(s, ""), "notes": derived[s] + [facts.item_note(s)]}
                  for s in sorted(derived) if s not in ids]
    flags = name_flags(facts, "hearthstones", shipped)
    for row in shipped:
        if facts.spell_names.get(row["id"]) and row["id"] not in derived:
            flags.append(_flag("unfit", "hearthstones", row, facts.spell_names[row["id"]]))
    order = {row["id"]: i for i, row in enumerate(shipped)}
    flags.sort(key=lambda f: (order[f["id"]], FLAG_KINDS["hearthstones"].index(f["kind"])))
    return candidates, flags


def derive_doc(tables: dict, flavor: str, build: str, date: str, hearth: Path = HEARTH_FILE,
               ignore: Path = IGNORE_FILE, fdb=None) -> dict:
    """The bundle's candidates.json for one flavor. `fdb` ({"db", "sources"}) is the ForeverDB
    evidence, required by a flavor that names it and refused by one that does not."""
    info = FLAVORS[flavor]
    if info["foreverdb"] != (fdb is not None):
        raise SystemExit("flavor %s %s ForeverDB evidence." % (flavor, "needs" if info["foreverdb"] else "never reads"))
    facts = Facts(tables)
    doc = {"client": flavor, "product": info["product"], "build": build, "date": date,
           "tool": "tools/seeds/seeds.py derive", "shipped": {}, "derived": {}, "candidates": [], "flags": []}
    if "hearthstones" in info["lists"]:
        derived = derive_hearthstones(facts)
        shipped_h = read_hearthstones(hearth)
        candidates, flags = hearth_findings(facts, derived, shipped_h)
        doc["shipped"]["hearthstones"] = len(shipped_h)
        doc["derived"]["hearthstones"] = [{"id": s, "name": facts.spell_names.get(s, ""), "rules": derived[s]}
                                          for s in sorted(derived)]
        doc["candidates"] += candidates
        doc["flags"] += flags
    seed = read_ignore(ignore, info["client"])
    rows = ignore_rows(seed)
    doc["shipped"]["ignore"] = len(rows)
    doc["ignore"] = {"lanes": seed["lanes"],
                     "checked": [{"id": r["id"], "file": r["name"], "build": facts.spell_names.get(r["id"], ""),
                                  "lanes": r["lanes"]} for r in rows]}
    doc["flags"] += name_flags(facts, "ignore", rows)
    if fdb is not None:
        src = fdb["sources"]
        dummies = derive_dummies(fdb["db"])
        doc["foreverdb"] = {"tag": src.get("tag"), "commit": src.get("commit"),
                            "meta": src.get("meta"), "json_sha256": (src.get("json") or {}).get("sha256")}
        doc["shipped"]["dummies"] = 0
        doc["candidates"] += [{"key": "dummies:%d" % d["id"], "list": "dummies", "id": d["id"],
                               "name": d["name"], "notes": d["notes"]} for d in dummies]
    return doc


# ---------------------------------------------------------------------------
# Bundles
# ---------------------------------------------------------------------------

def bundles(root: Path, flavor: str) -> list:
    """Every bundle of `flavor` under `root` that holds a candidates.json, oldest first."""
    return sorted(p for p in root.glob("*-" + flavor) if (p / "candidates.json").exists())


def bundle_doc(bundle: Path) -> dict:
    return json.loads((bundle / "candidates.json").read_text(encoding="utf-8"))


def status_line(live: str, found: list, tag=None) -> str:
    """`CURRENT <build> (<bundle>)`, or `NEW <build> ...`; the first word is what the command reads.
    With a ForeverDB `tag`, a bundle is current only when its build and its tag both match."""
    shown = live if tag is None else "%s + ForeverDB %s" % (live, tag)
    if not found:
        return "NEW %s (no bundle yet)" % shown
    doc = bundle_doc(found[-1])
    built = doc["build"] if tag is None else "%s + ForeverDB %s" % (doc["build"], (doc.get("foreverdb") or {}).get("tag"))
    if built == shown:
        return "CURRENT %s (%s)" % (shown, found[-1].name)
    return "NEW %s (last ruled %s, %s)" % (shown, built, found[-1].name)


def sources_md(flavor: str, build: str, date: str, replay: bool, fdb=None, script=None) -> str:
    info = FLAVORS[flavor]
    lines = ["# Sources — seed validation, %s (%s)" % (date, flavor), "",
             "Generated by `tools/seeds/seeds.py derive`. Frozen: this directory is never edited after",
             "the run, apart from the hand-written `ANALYSIS.md`.", "",
             "| Field | Value |", "| --- | --- |",
             "| Client | `%s` (%s, wago product `%s`) |" % (flavor, info["title"], info["product"]),
             "| Build | `%s` |" % build,
             "| Fetched | %s%s |" % (date, " (replayed from raw/)" if replay else ""),
             "| Builds API | <%s> |" % BUILDS_URL,
             "| User-Agent | `%s` |" % USER_AGENT, "", "## Tables", "",
             "| Table | Why | URL |", "| --- | --- | --- |"]
    lines += ["| `%s` | %s | <%s> |" % (t, why, CSV_URL.format(table=t, build=build)) for t, why in info["tables"]]
    lines += ["", "The gzipped exports are in `raw/`. Re-derive offline with `--replay`; a new run needs",
              "network access to wago.tools.", ""]
    if fdb is not None:
        lines += foreverdb_md(fdb["sources"], script)
    return "\n".join(lines)


def foreverdb_md(src: dict, script=None) -> list:
    """SOURCES.md's ForeverDB section: the tag, commit, hashes and URLs, never a row."""
    install, meta = src.get("install") or {}, src.get("meta") or {}
    commit = script_commit(script) if script else ""
    lines = ["## ForeverDB (evidence, GPL-3.0: no rows kept here)", "",
             "| Field | Value |", "| --- | --- |",
             "| Repository | <%s> |" % src.get("repository", ""),
             "| Tag | `%s` |" % src.get("tag", ""),
             "| Commit | `%s` |" % (src.get("commit") or "unknown"),
             "| TOC version | `%s` |" % src.get("tocVersion", ""),
             "| meta.build, meta.hash | `%s`, `%s` |" % (meta.get("build"), meta.get("hash")),
             "| Read from | %s |" % " + ".join(src.get("origin") or []),
             "| Owner's install | %s |" % (("version `%s`" % install["version"]) if install.get("version") else "not read"),
             "| Cache date | %s |" % src.get("date", ""),
             "| Helper | `foreverdb.py`%s |" % ((" (dev-copilot `%s`)" % commit) if commit else ""),
             "| foreverdb.json sha256 | `%s` |" % (src.get("json") or {}).get("sha256", ""), "",
             "| File | Bytes | sha256 |", "| --- | --- | --- |"]
    lines += ["| `%s` | %s | `%s` |" % (f["path"], f["bytes"], f["sha256"]) for f in src.get("files") or []]
    lines += ["", "URLs:", ""] + ["- <%s>" % url for url in src.get("urls") or []]
    return lines + ["", "A replay re-fetches the pinned tag, which is immutable, through the helper; the bundle",
                    "keeps only per-id verdicts (`candidates.json`: an id and its name).", ""]


def _count_row(doc: dict, lst: str) -> str:
    derived = doc["derived"].get(lst)
    return "| `%s` | %d | %s | %d | %d |" % (
        lst, doc["shipped"].get(lst, 0), len(derived) if derived is not None else "not derived",
        len([c for c in doc["candidates"] if c["list"] == lst]), len([f for f in doc["flags"] if f["list"] == lst]))


def _ignore_table(checked: list) -> list:
    lines = ["", "## Ignore seeds checked", "", "| Id | Lanes | File name | Build name |", "| --- | --- | --- | --- |"]
    return lines + ["| `%d` | %s | %s | %s |" % (r["id"], ", ".join(r["lanes"]), r["file"] or "(none)",
                                                 r["build"] or "(no row)") for r in checked]


def diff_md(doc: dict) -> str:
    lines = ["# Diff — derived against shipped, %s (%s, build %s)" % (doc["date"], doc["client"], doc["build"]), "",
             "Generated by `tools/seeds/seeds.py derive`.", "",
             "| List | Shipped | Derived | Derived, not shipped | Flags |", "| --- | --- | --- | --- | --- |"]
    lines += [_count_row(doc, lst) for lst in FLAVORS[doc["client"]]["lists"]]
    lines += ["", "## Derived, not shipped", ""]
    lines += ["- `%s` %s" % (c["key"], c["name"] or "(no name)") for c in doc["candidates"]] or ["None."]
    if "ignore" in doc:
        lines += _ignore_table(doc["ignore"]["checked"])
    lines += ["", "## Shipped, flagged", ""]
    lines += ["- `%s` %s (file: %s)" % (f["key"], f["name"] or "(no row)", f["comment"] or "-")
              for f in doc["flags"]] or ["None."]
    return "\n".join(lines + [""])


def load_doc(bundle: Path) -> dict:
    path = bundle / "candidates.json"
    if not path.exists():
        raise SystemExit("%s has no candidates.json: run seeds.py derive first." % bundle)
    return json.loads(path.read_text(encoding="utf-8"))


def all_keys(doc: dict) -> list:
    return [c["key"] for c in doc["candidates"]] + [f["key"] for f in doc["flags"]]


def unruled_keys(doc: dict, rulings: dict) -> list:
    return [key for key in all_keys(doc) if key not in rulings]


# ---------------------------------------------------------------------------
# Rulings (data, keyed by list and id, never by build; one file per flavor)
# ---------------------------------------------------------------------------

def rulings_path(flavor: str) -> Path:
    return HERE / ("%s_rulings.json" % flavor)


def load_rulings(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save_rulings(path: Path, rulings: dict) -> None:
    write_repo_text(path, json.dumps(rulings, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def read_tsv(path: Path) -> list:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit("%s: a ruling line is key<TAB>ruling<TAB>reason; got %r" % (path, line))
        out.append(tuple(p.strip() for p in parts))
    return out


def set_ruling(rulings: dict, key: str, ruling: str, reason: str) -> None:
    """Record one ruling; a malformed key, ruling or reason is a SystemExit naming it."""
    match = KEY.match(key)
    if not match or match.group("list") not in LISTS:
        raise SystemExit("%r is not <list>:<id> or shipped:<kind>:<list>:<id>." % key)
    kind, lst = match.group("kind"), match.group("list")
    if kind and kind not in FLAG_KINDS[lst]:
        raise SystemExit("%r: %s has no flag kind %r." % (key, lst, kind))
    if not kind and lst not in CANDIDATE_RULINGS:
        raise SystemExit("%r: %s takes no candidates (it is curated, not derived)." % (key, lst))
    allowed = FLAG_RULINGS if kind else CANDIDATE_RULINGS[lst]
    if ruling not in allowed:
        raise SystemExit("the ruling for %s must be %s; got %r." % (key, " or ".join(allowed), ruling))
    reason = (reason or "").strip()
    if not reason or "\n" in reason:
        raise SystemExit("the reason for %s must be one non-empty line." % key)
    rulings[key] = {"ruling": ruling, "reason": reason}


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

def hearth_line(spell: int, name: str) -> str:
    return "    " + (str(spell) + ",").ljust(10) + "-- " + name


def _insert_hearthstones(body: list, inserts: list) -> list:
    """Insert each new `(id, name)` into `body` ([(id, line)]) in ascending order after rule 3's
    fixed rows; returns the change log."""
    changes, present = [], {spell for spell, _line in body}
    for spell, name in sorted(inserts):
        if spell in present:
            continue
        at = next((i for i, (other, _line) in enumerate(body) if other not in FIXED and other > spell), len(body))
        body.insert(at, (spell, hearth_line(spell, name)))
        present.add(spell)
        changes.append("hearthstones: +%d %s" % (spell, name))
    return changes


def apply_hearthstones(path: Path, inserts: list, removals: set) -> list:
    """Insert accepted ids in ascending order after rule 3's fixed rows, remove ruled ids; returns
    the change log. Keeps the file's own newline and every other byte."""
    if not inserts and not removals:
        return []
    lines, newline = split_lines(path.read_bytes().decode("utf-8"))
    start = next(i for i, line in enumerate(lines) if HEARTH_TABLE_OPEN.match(line))
    end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "}")
    changes, body = [], []
    for line in lines[start + 1:end]:
        spell = int(HEARTH_ROW.match(line).group(1))
        if spell in removals:
            changes.append("hearthstones: -%d" % spell)
            continue
        body.append((spell, line))
    changes += _insert_hearthstones(body, inserts)
    if changes:
        out = lines[:start + 1] + [line for _s, line in body] + lines[end:]
        path.write_bytes(newline.join(out).encode("utf-8"))
    return changes


def apply_ignore(path: Path, client: str, removals: set) -> list:
    """Remove ruled ids from one client's lanes in NS.IgnoreSeeds; returns the change log. Keeps
    the file's own newline, each lane line's layout and every other byte."""
    if not removals:
        return []
    lines, newline = split_lines(path.read_bytes().decode("utf-8"))
    start, end = _ignore_block(lines, path)
    changes, current = [], None
    for i in range(start + 1, end):
        opened = IGNORE_CLIENT.match(lines[i])
        if opened:
            current = opened.group(1)
            continue
        lane = IGNORE_LANE.match(lines[i])
        if not lane or current != client:
            continue
        ids = _ids(lane.group(4))
        kept = [s for s in ids if s not in removals]
        if kept != ids:
            changes += ["ignore %s.%s: -%d" % (client, lane.group(2), s) for s in ids if s in removals]
            inner = " %s " % ", ".join(str(s) for s in kept) if kept else ""
            lines[i] = "%s%s%s{%s}%s" % (lane.group(1), lane.group(2), lane.group(3), inner, lane.group(5))
    if changes:
        path.write_bytes(newline.join(lines).encode("utf-8"))
    return changes


def apply_doc(doc: dict, rulings: dict, hearth: Path = HEARTH_FILE, ignore: Path = IGNORE_FILE) -> list:
    unruled = unruled_keys(doc, rulings)
    if unruled:
        raise SystemExit("apply refused: %d key(s) unruled (seeds.py check lists them)." % len(unruled))
    accepted = [c for c in doc["candidates"] if rulings[c["key"]]["ruling"] == "accept"]
    if any(c["list"] != "hearthstones" for c in accepted):
        raise SystemExit("apply refused: only hearthstones take an accepted candidate.")
    removed = {lst: {f["id"] for f in doc["flags"] if f["list"] == lst and rulings[f["key"]]["ruling"] == "remove"}
               for lst in ("hearthstones", "ignore")}
    changes = apply_hearthstones(hearth, [(c["id"], c["name"]) for c in accepted], removed["hearthstones"])
    return changes + apply_ignore(ignore, FLAVORS[doc["client"]]["client"], removed["ignore"])


# ---------------------------------------------------------------------------
# RULINGS.md
# ---------------------------------------------------------------------------

def _cell(text) -> str:
    return (text or "").replace("|", "\\|")


def rulings_md(doc: dict, rulings: dict, date: str, rulings_file: str) -> str:
    tally = {}
    for key in all_keys(doc):
        r = rulings.get(key, {}).get("ruling", "unruled")
        tally[r] = tally.get(r, 0) + 1
    unruled = unruled_keys(doc, rulings)
    shipped = ", ".join("%d %s" % (n, lst) for lst, n in sorted(doc["shipped"].items()))
    lines = ["# Rulings — seed validation, %s (%s, build %s)" % (doc["date"], doc["client"], doc["build"]), "",
             "Generated by `tools/seeds/seeds.py report` on %s from this bundle's `candidates.json` and" % date,
             "`tools/seeds/%s`. Do not edit by hand." % rulings_file, "",
             "Shipped: %s. %d candidates, %d flags: %s." % (
                 shipped, len(doc["candidates"]), len(doc["flags"]),
                 ", ".join("%d %s" % (n, r) for r, n in sorted(tally.items())) or "none"), ""]
    if unruled:
        lines += ["## Unruled — %d" % len(unruled), ""] + ["- `%s`" % k for k in unruled] + [""]
    for lst in FLAVORS[doc["client"]]["lists"]:
        if lst in CANDIDATE_RULINGS:
            lines += _candidate_section(lst, [c for c in doc["candidates"] if c["list"] == lst], rulings)
    return "\n".join(lines + _flag_section(doc["flags"], rulings) + [""])


def _candidate_section(lst: str, cands: list, rulings: dict) -> list:
    lines = ["## Candidates — %s" % lst, ""]
    if not cands:
        return lines + ["None: the build proposes nothing the list does not ship.", ""]
    lines += ["| Id | Name | Notes | Ruling | Reason |", "| --- | --- | --- | --- | --- |"]
    for c in cands:
        r = rulings.get(c["key"], {})
        lines.append("| `%d` | %s | %s | %s | %s |" % (c["id"], _cell(c["name"]), _cell("; ".join(c["notes"])),
                                                       r.get("ruling", "**unruled**"), _cell(r.get("reason"))))
    return lines + [""]


def _flag_section(flags: list, rulings: dict) -> list:
    lines = ["## Shipped-id flags — %d" % len(flags), ""]
    if not flags:
        return lines + ["None."]
    lines += ["| Kind | List | Id | Build name | File name | Ruling | Reason |",
              "| --- | --- | --- | --- | --- | --- | --- |"]
    for f in flags:
        r = rulings.get(f["key"], {})
        lines.append("| %s | %s | `%d` | %s | %s | %s | %s |" % (
            f["kind"], f["list"], f["id"], _cell(f["name"]) or "(no row)", _cell(f["comment"]),
            r.get("ruling", "**unruled**"), _cell(r.get("reason"))))
    return lines


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def _date(value: str) -> str:
    if not DATE_RE.match(value):
        raise argparse.ArgumentTypeError("a date is YYYY-MM-DD; got %r" % value)
    return value


def _rulings_for(args, flavor: str) -> Path:
    return args.rulings or rulings_path(flavor)


def cmd_status(args) -> int:
    info = FLAVORS[args.flavor]
    if info["foreverdb"] and not args.foreverdb:
        raise SystemExit("status --flavor %s needs --foreverdb <tag> (foreverdb.py status prints it)." % args.flavor)
    tag = args.foreverdb if info["foreverdb"] else None
    print(status_line(live_build(info["product"]), bundles(args.root, args.flavor), tag))
    return 0


def _derive_build(args, info: dict, old: dict) -> str:
    """The build a derive pins: `--build`, else the replayed bundle's own, else the newest live one."""
    if not args.replay:
        return args.build or live_build(info["product"])
    build = args.build or old.get("build")
    if not build:
        raise SystemExit("--replay %s has no candidates.json to take its build from; pass --build." % args.bundle)
    return build


def _derive_foreverdb(args, info: dict, old: dict):
    """The ForeverDB evidence a derive reads, or None for a flavor that never reads it."""
    if not info["foreverdb"]:
        if args.foreverdb:
            raise SystemExit("flavor %s never reads ForeverDB (clients-§10)." % args.flavor)
        return None
    tag = args.foreverdb or (old.get("foreverdb") or {}).get("tag")
    if not tag:
        raise SystemExit("derive --flavor %s needs --foreverdb <tag>." % args.flavor)
    return load_foreverdb(foreverdb_fetch(args.foreverdb_script, tag, args.date, args.foreverdb_install))


def cmd_derive(args) -> int:
    info = FLAVORS[args.flavor]
    if not args.bundle.name.endswith("-" + args.flavor):
        raise SystemExit("--bundle %s: a %s bundle is named <date>-%s." % (args.bundle, args.flavor, args.flavor))
    old = bundle_doc(args.bundle) if (args.bundle / "candidates.json").exists() else {}
    build, fdb = _derive_build(args, info, old), _derive_foreverdb(args, info, old)
    log("Build %s (%s)" % (build, args.flavor))
    tables = freeze_tables(args.bundle, build, args.cache_dir, args.replay, info["tables"])
    doc = derive_doc(tables, args.flavor, build, args.date, args.hearthstones, args.ignore, fdb)
    write_json(args.bundle / "candidates.json", doc)
    write_repo_text(args.bundle / "SOURCES.md",
                    sources_md(args.flavor, build, args.date, args.replay, fdb, args.foreverdb_script))
    write_repo_text(args.bundle / "DIFF.md", diff_md(doc))
    unruled = unruled_keys(doc, load_rulings(_rulings_for(args, args.flavor)))
    for lst in info["lists"]:
        log(_count_row(doc, lst))
    log("%d candidates, %d flags, %d unruled" % (len(doc["candidates"]), len(doc["flags"]), len(unruled)))
    return 0


def cmd_rule(args) -> int:
    todo = [(key, args.ruling, args.reason) for key in (args.key or ())]
    if args.tsv:
        todo += read_tsv(args.tsv)
    if not todo:
        raise SystemExit("rule needs --key (with --ruling and --reason) or --tsv.")
    doc = load_doc(args.bundle)
    known = set(all_keys(doc))
    path = _rulings_for(args, doc["client"])
    rulings = load_rulings(path)
    for key, ruling, reason in todo:
        if key not in known:
            raise SystemExit("%s is not a candidate or flag in %s/candidates.json." % (key, args.bundle))
        set_ruling(rulings, key, ruling, reason)
    save_rulings(path, rulings)
    log("Recorded %d ruling(s) in %s" % (len(todo), path))
    return 0


def cmd_check(args) -> int:
    doc = load_doc(args.bundle)
    unruled = unruled_keys(doc, load_rulings(_rulings_for(args, doc["client"])))
    if not unruled:
        print("OK: every candidate and flag in %s is ruled." % args.bundle.name)
        return 0
    rows = {c["key"]: c for c in doc["candidates"]}
    rows.update({f["key"]: f for f in doc["flags"]})
    print("%d unruled:" % len(unruled))
    for key in unruled:
        row = rows[key]
        print("  %s  %s (file: %s)" % (key, row["name"] or "(no row)", row.get("comment") or "-"))
    return 1


def cmd_report(args) -> int:
    doc = load_doc(args.bundle)
    path = _rulings_for(args, doc["client"])
    write_repo_text(args.bundle / "RULINGS.md", rulings_md(doc, load_rulings(path), args.date, path.name))
    log("Wrote %s" % (args.bundle / "RULINGS.md"))
    return 0


def cmd_apply(args) -> int:
    doc = load_doc(args.bundle)
    changes = apply_doc(doc, load_rulings(_rulings_for(args, doc["client"])), args.hearthstones, args.ignore)
    for line in changes:
        log("  " + line)
    log("%d change(s)" % len(changes))
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Re-validate Combat Trail's seed lists against a wago.tools build.",
                                     epilog="The contract: docs/validate-seeds.md.")
    parser.add_argument("--rulings", type=Path, default=None,
                        help="the rulings file (default: tools/seeds/<flavor>_rulings.json)")
    parser.add_argument("--hearthstones", type=Path, default=HEARTH_FILE)
    parser.add_argument("--ignore", type=Path, default=IGNORE_FILE)
    parser.add_argument("--cache-dir", type=Path, default=CACHE_DIR)
    sub = parser.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status", help="is there a live build (or ForeverDB tag) newer than the newest bundle?")
    status.add_argument("--flavor", choices=sorted(FLAVORS), required=True)
    status.add_argument("--root", type=Path, default=RESEARCH)
    status.add_argument("--foreverdb", default=None, help="forever: the newest ForeverDB tag")
    derive = sub.add_parser("derive", help="freeze one build's tables; candidates and flags into candidates.json")
    derive.add_argument("--flavor", choices=sorted(FLAVORS), required=True)
    derive.add_argument("--bundle", type=Path, required=True)
    derive.add_argument("--date", type=_date, required=True)
    derive.add_argument("--build", default=None, help="pin this build (default: the flavor's newest live build)")
    derive.add_argument("--replay", action="store_true", help="read only the bundle's raw/ for the DB2 tables")
    derive.add_argument("--foreverdb", default=None, help="forever: pin this ForeverDB tag")
    derive.add_argument("--foreverdb-script", type=Path, default=None, help="forever: dev-copilot's scripts/foreverdb.py")
    derive.add_argument("--foreverdb-install", type=Path, default=None,
                        help="forever: read an installed AddOns/ForeverDB folder (read-only) instead of GitHub")
    rule = sub.add_parser("rule", help="record rulings (the only writer of the rulings files)")
    rule.add_argument("--key", action="append")
    rule.add_argument("--ruling")
    rule.add_argument("--reason")
    rule.add_argument("--tsv", type=Path, help="key<TAB>ruling<TAB>reason lines")
    rule.add_argument("--bundle", type=Path, required=True, help="the bundle the keys come from (and its flavor)")
    for name, helptext in (("check", "exit 1 while anything is unruled"),
                           ("report", "write the bundle's RULINGS.md"),
                           ("apply", "write accepted ids and ruled removals into the seed files")):
        cmd = sub.add_parser(name, help=helptext)
        cmd.add_argument("--bundle", type=Path, required=True)
        if name != "check":
            cmd.add_argument("--date", type=_date, required=True)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    return {"status": cmd_status, "derive": cmd_derive, "rule": cmd_rule, "check": cmd_check,
            "report": cmd_report, "apply": cmd_apply}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
