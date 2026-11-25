"""Tests for tools/seeds/seeds.py (docs/validate-seeds.md). No network: every case reads the tiny
CSVs in tools/seeds/fixtures/ or a temp copy of them, temp seed files and an invented ForeverDB
(never ForeverDB's own rows: its data is GPL-3.0, so every id here is 900000+ and every name made
up); the last cases read the repo's own seed files, rulings and newest bundles.

Mutation-checked (2026-11-25): with the rule-4 guard in `derive_hearthstones` broken (the
`out.pop(spell, None)` loop over EXCLUDED deleted), `test_rule_4_removes_excluded_ids` and
`test_four_rules` fail; with `DUMMY_NAME` matching nothing, `test_dummies_from_foreverdb` fails;
with `name_flags`' renamed branch deleted, `test_ignore_flags` fails; restored, they pass.
Mutation-checked (2026-11-25, CL-13a): with `derive_buffs`' aura guard deleted, `test_buff_rule` fails;
with a shipped BuffSeeds id dropped from the repo's file, `test_shipped_buffs_match_the_rulings` fails;
with `apply_buffs` writing into the other client's block, `test_apply_buffs_*` fail; restored, they pass.

Run: python3 -m pytest -q -p no:cacheprovider tools/seeds   (or: python3 -m unittest discover -s tools/seeds)
"""

from __future__ import annotations

import gzip
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import seeds  # noqa: E402

FIXTURES = HERE / "fixtures"

SEED = (
    "local _, NS = ...\r\n"
    "-- header\r\n"
    "\r\n"
    "NS.HEARTHSTONE_SPELLS = {\r\n"
    "    8690,     -- Hearthstone\r\n"
    "    222695,   -- Dalaran Hearthstone\r\n"
    "    171253,   -- Garrison Hearthstone\r\n"
    "    700001,   -- Scroll of Recall\r\n"
    "    700003,   -- Wrong Name\r\n"
    "    900001,   -- Old Toy\r\n"
    "    950000,   -- Gone\r\n"
    "}\r\n"
)

IGNORE = (
    "local _, NS = ...\r\n"
    "-- defaults/IgnoreSeeds.lua — invented ids.\r\n"
    "--\r\n"
    "-- player  Auto Swing 700100, Auto Volley 700101, Shoot Wand 700102 (a wand), on both clients.\r\n"
    "-- pet     Auto Swing 700100, Pet Claw 700103, on both clients. More words here.\r\n"
    "--         a continuation line with 12 in it\r\n"
    "\r\n"
    "NS.IgnoreSeeds = {\r\n"
    "    Retail = {\r\n"
    "        player = { 700100, 700101, 700102 },\r\n"
    "        pet    = { 700100, 700103 },\r\n"
    "    },\r\n"
    "    Forever = {\r\n"
    "        player = { 700100, 700102 },\r\n"
    "        pet    = { 700100 },\r\n"
    "    },\r\n"
    "}\r\n"
    "\r\n"
    "NS.IGNORE_SEEDS = NS.IgnoreSeeds.Retail\r\n"
)

BUFFS = (
    "local _, NS = ...\r\n"
    "-- defaults/BuffSeeds.lua — invented rows.\r\n"
    "\r\n"
    "NS.BuffSeeds = {\r\n"
    "    Retail = {\r\n"
    "        foodSubclass = 5,\r\n"
    "        buffs = {\r\n"
    "            15366,    -- Songflower Serenade\r\n"
    "            22888,    -- Wrong Name\r\n"
    "            700203,   -- Songflower Serenade\r\n"
    "            950001,   -- Gone\r\n"
    "        },\r\n"
    "        wellFed = {\r\n"
    "            19705,\r\n"
    "        },\r\n"
    "    },\r\n"
    "    Forever = {\r\n"
    "        foodSubclass = 8,\r\n"
    "        buffs = {\r\n"
    "            1229741,  -- Camp Benefits\r\n"
    "        },\r\n"
    "        wellFed = {\r\n"
    "        },\r\n"
    "    },\r\n"
    "}\r\n"
    "\r\n"
    "NS.BUFF_SEEDS = NS.BuffSeeds.Retail\r\n"
)

# An invented ForeverDB in the real shape: npc[id] = {name, sub, minLv, maxLv, rank}, spm["c<id>"] =
# {[uiMap] = {x, y, ...}}. No real row.
FAKE_FDB = {
    "db": {
        "meta": {"build": "2000-01-01", "hash": "feedface"},
        "npc": {"900001": ["Practice Dummy Of Tests", None, 1, 1, 0],
                "900002": ["Dummyhead the Unrelated", None, 5, 5, 0],
                "900003": ["Target dummy", "Invented", 1, 1, 0],
                "900004": ["Innkeeper Nobody", None, 30, 30, 0],
                "900005": 7},
        "spm": {"c900003": {"9001": [100, 200]}},
    },
    "sources": {"tag": "v2000.01.01.1", "commit": "0" * 40, "meta": {"build": "2000-01-01", "hash": "feedface"},
                "json": {"sha256": "ab" * 32}, "files": [{"path": "ForeverDB/ForeverDB.toc", "bytes": 1,
                                                         "sha256": "cd" * 32}],
                "origin": ["github"], "urls": ["https://example.invalid/ForeverDB.toc"],
                "repository": "https://example.invalid/forever-db", "tocVersion": "2000.01.01.1",
                "date": "2000-01-01"},
}


def fixture_tables(flavor: str = "retail", root: Path = FIXTURES) -> dict:
    return {table: root / ("%s.csv" % table) for table, _why in seeds.FLAVORS[flavor]["tables"]}


class Workspace(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.seed = self.tmp / "Hearthstones.lua"
        self.seed.write_bytes(SEED.encode("utf-8"))
        self.ignore = self.tmp / "IgnoreSeeds.lua"
        self.ignore.write_bytes(IGNORE.encode("utf-8"))
        self.buffs = self.tmp / "BuffSeeds.lua"
        self.buffs.write_bytes(BUFFS.encode("utf-8"))
        self.facts = seeds.Facts(fixture_tables())

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def doc(self, flavor: str = "retail"):
        return seeds.derive_doc(fixture_tables(flavor), flavor, "1.2.3.4", "2026-01-02", self.seed, self.ignore,
                                FAKE_FDB if flavor == "forever" else None, self.buffs)

    def apply(self, doc, rulings):
        return seeds.apply_doc(doc, rulings, self.seed, self.ignore, self.buffs)


class TestRules(Workspace):
    def test_four_rules(self):
        derived = seeds.derive_hearthstones(self.facts)
        self.assertEqual(sorted(derived), [8690, 171253, 222695, 700001, 700003, 700010, 700011,
                                           700012, 1310840])

    def test_rule_1_reads_every_difficulty_and_rule_2_either_target_slot(self):
        derived = seeds.derive_hearthstones(self.facts)
        self.assertIn("rule 1: ChargeCategory 2309", derived[700003], "a DifficultyID 1 row counts")
        self.assertIn("rule 2: Effect 252, ImplicitTarget 9", derived[700010], "slot 0")
        self.assertIn("rule 2: Effect 252, ImplicitTarget 9", derived[700011], "slot 1")
        self.assertNotIn(700013, derived, "a teleport elsewhere is no hearthstone")
        self.assertNotIn(700002, derived, "another charge category is not the hearthstone's")

    def test_rule_4_removes_excluded_ids(self):
        derived = seeds.derive_hearthstones(self.facts)
        self.assertNotIn(556, derived)
        self.assertNotIn(1223998, derived)

    def test_sentinel_gate_stops_a_thin_run(self):
        self.facts.spell_names.pop(8690)
        with self.assertRaises(SystemExit) as err:
            seeds.derive_hearthstones(self.facts)
        self.assertIn("8690", str(err.exception))

    def test_item_note(self):
        self.assertEqual(self.facts.item_note(700010), "cast by toy 5000")
        self.assertEqual(self.facts.item_note(700001), "cast by item 5002")
        self.assertEqual(self.facts.item_note(700011), "triggered by 700020, which an item casts")
        self.assertEqual(self.facts.item_note(700012), "no item casts it")

    def test_newest_live_skips_background_downloads(self):
        builds = [{"version": "9.9", "is_bgdl": True}, {"version": "9.8", "is_bgdl": False}]
        self.assertEqual(seeds.newest_live(builds), "9.8")
        with self.assertRaises(SystemExit):
            seeds.newest_live([{"version": "9.9", "is_bgdl": True}])


class TestIgnore(Workspace):
    def test_read_ignore_per_client_with_header_names(self):
        retail = seeds.read_ignore(self.ignore, "Retail")
        self.assertEqual(retail["lanes"], {"player": [700100, 700101, 700102], "pet": [700100, 700103]})
        self.assertEqual(retail["names"], {700100: "Auto Swing", 700101: "Auto Volley", 700102: "Shoot Wand",
                                           700103: "Pet Claw"})
        forever = seeds.read_ignore(self.ignore, "Forever")
        self.assertEqual(forever["lanes"], {"player": [700100, 700102], "pet": [700100]})
        rows = seeds.ignore_rows(retail)
        self.assertEqual([(r["id"], r["lanes"]) for r in rows],
                         [(700100, ["player", "pet"]), (700101, ["player"]), (700102, ["player"]), (700103, ["pet"])])

    def test_ignore_flags(self):
        doc = self.doc()
        flags = sorted(f["key"] for f in doc["flags"] if f["list"] == "ignore")
        self.assertEqual(flags, ["shipped:renamed:ignore:700102", "shipped:unnamed:ignore:700103"])
        self.assertEqual(doc["shipped"]["ignore"], 4)
        forever = self.doc("forever")
        self.assertEqual(sorted(f["key"] for f in forever["flags"] if f["list"] == "ignore"),
                         ["shipped:renamed:ignore:700102"])

    def test_apply_removes_from_the_flavor_client_only(self):
        doc = self.doc()
        rulings = {k: {"ruling": "reject", "reason": "x"} for k in seeds.all_keys(doc)}
        for f in doc["flags"]:
            rulings[f["key"]] = {"ruling": "keep", "reason": "x"}
        rulings["shipped:renamed:ignore:700102"] = {"ruling": "remove", "reason": "reused"}
        changes = self.apply(doc, rulings)
        self.assertEqual(changes, ["ignore Retail.player: -700102"])
        text = self.ignore.read_bytes().decode("utf-8")
        self.assertIn("        player = { 700100, 700101 },\r\n", text)
        self.assertIn("        player = { 700100, 700102 },\r\n", text, "Forever keeps its own list")
        self.assertNotIn("\n", text.replace("\r\n", ""), "every terminator stays CRLF")
        self.assertEqual(self.apply(doc, rulings), [])


class TestForever(Workspace):
    def test_dummies_from_foreverdb(self):
        found = seeds.derive_dummies(FAKE_FDB["db"])
        self.assertEqual([(d["id"], d["name"]) for d in found],
                         [(900001, "Practice Dummy Of Tests"), (900003, "Target dummy")])
        self.assertEqual(found[1]["notes"], ["ForeverDB creature name match", "spawn recorded on 1 map(s)"])
        self.assertEqual(found[0]["notes"][1], "no spawn recorded")

    def test_forever_doc_reads_spellname_and_foreverdb_only(self):
        doc = self.doc("forever")
        self.assertNotIn("hearthstones", doc["shipped"])
        self.assertEqual([c["key"] for c in doc["candidates"] if c["list"] == "dummies"],
                         ["dummies:900001", "dummies:900003"])
        self.assertEqual(doc["foreverdb"]["tag"], "v2000.01.01.1")
        self.assertNotIn("Innkeeper", json.dumps(doc), "no other ForeverDB row reaches the bundle")
        self.assertNotIn("Invented", json.dumps(doc), "not even a matched row's other fields")
        self.assertEqual(sorted(fixture_tables("forever")), ["Item", "ItemEffect", "ItemXItemEffect", "SpellEffect",
                                                             "SpellName"], "no SpellCategories or Toy")

    def test_foreverdb_is_forever_only(self):
        with self.assertRaises(SystemExit):
            seeds.derive_doc(fixture_tables(), "retail", "1", "2026-01-02", self.seed, self.ignore, FAKE_FDB, self.buffs)
        with self.assertRaises(SystemExit):
            seeds.derive_doc(fixture_tables("forever"), "forever", "1", "2026-01-02", self.seed, self.ignore, None,
                             self.buffs)

    def test_dummies_take_reject_only(self):
        rulings = {}
        seeds.set_ruling(rulings, "dummies:900001", "reject", "empty by decision")
        with self.assertRaises(SystemExit):
            seeds.set_ruling({}, "dummies:900001", "accept", "x")
        with self.assertRaises(SystemExit):
            seeds.set_ruling({}, "ignore:700100", "accept", "x")
        doc = self.doc("forever")
        forged = {k: {"ruling": "keep", "reason": "x"} for k in seeds.all_keys(doc)}
        forged["dummies:900001"] = {"ruling": "accept", "reason": "forged"}
        forged["dummies:900003"] = {"ruling": "reject", "reason": "x"}
        with self.assertRaises(SystemExit):
            self.apply(doc, forged)

    def test_sources_md_keeps_hashes_and_no_rows(self):
        text = seeds.sources_md("forever", "1.2.3.4", "2026-01-02", False, FAKE_FDB)
        self.assertIn("`v2000.01.01.1`", text)
        self.assertIn("cd" * 32, text)
        self.assertNotIn("Practice Dummy", text)

    def test_status_line_with_a_tag(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            b = root / "2026-01-02-forever"
            b.mkdir()
            (b / "candidates.json").write_text(json.dumps({"build": "1.6", "foreverdb": {"tag": "v1"}}))
            found = seeds.bundles(root, "forever")
            self.assertTrue(seeds.status_line("1.6", found, "v1").startswith("CURRENT "))
            self.assertTrue(seeds.status_line("1.6", found, "v2").startswith("NEW "), "a new tag is a run")
            self.assertTrue(seeds.status_line("1.7", found, "v1").startswith("NEW "), "a new build is a run")


class TestFindings(Workspace):
    def test_candidates_and_flags(self):
        doc = self.doc()
        self.assertEqual([c["key"] for c in doc["candidates"] if c["list"] == "hearthstones"],
                         ["hearthstones:700010", "hearthstones:700011", "hearthstones:700012",
                          "hearthstones:1310840"])
        self.assertEqual(sorted(f["key"] for f in doc["flags"] if f["list"] == "hearthstones"),
                         ["shipped:renamed:hearthstones:700003", "shipped:unfit:hearthstones:900001",
                          "shipped:unnamed:hearthstones:950000"])
        self.assertEqual(doc["shipped"], {"hearthstones": 7, "ignore": 4, "buffs": 4, "wellfed": 1, "food": 1})
        renamed = next(f for f in doc["flags"] if f["kind"] == "renamed" and f["list"] == "hearthstones")
        self.assertEqual((renamed["name"], renamed["comment"]), ("Heroic Hearthstone", "Wrong Name"))

    def test_replay_from_gzipped_raw_matches(self):
        bundle = self.tmp / "2026-01-02-retail"
        raw = bundle / "raw"
        raw.mkdir(parents=True)
        for table, path in fixture_tables().items():
            with path.open("rb") as src, gzip.open(raw / ("%s.csv.gz" % table), "wb") as dst:
                shutil.copyfileobj(src, dst)
        replayed = seeds.freeze_tables(bundle, "1.2.3.4", self.tmp / "cache", True, seeds.RETAIL_TABLES)
        b = seeds.derive_doc(replayed, "retail", "1.2.3.4", "2026-01-02", self.seed, self.ignore, None, self.buffs)
        self.assertEqual(self.doc(), b)
        (raw / "Toy.csv.gz").unlink()
        with self.assertRaises(SystemExit):
            seeds.freeze_tables(bundle, "1.2.3.4", self.tmp / "cache", True, seeds.RETAIL_TABLES)

    def test_freeze_from_cache_is_byte_stable(self):
        cache = self.tmp / "cache"
        cache.mkdir()
        for table, path in fixture_tables().items():
            shutil.copyfile(path, cache / ("%s-1.2.3.4.csv" % table))
        bundle = self.tmp / "b-retail"
        seeds.freeze_tables(bundle, "1.2.3.4", cache, False, seeds.RETAIL_TABLES)
        first = (bundle / "raw" / "SpellName.csv.gz").read_bytes()
        seeds.freeze_tables(bundle, "1.2.3.4", cache, False, seeds.RETAIL_TABLES)
        self.assertEqual(first, (bundle / "raw" / "SpellName.csv.gz").read_bytes())


class TestRulings(unittest.TestCase):
    def test_set_ruling_validates(self):
        rulings = {}
        seeds.set_ruling(rulings, "hearthstones:5", "accept", "a toy")
        seeds.set_ruling(rulings, "shipped:unnamed:hearthstones:6", "keep", "harmless")
        seeds.set_ruling(rulings, "shipped:renamed:ignore:7", "keep", "same spell")
        self.assertEqual(rulings["hearthstones:5"], {"ruling": "accept", "reason": "a toy"})
        for key, ruling, reason in (("bogus:5", "accept", "x"), ("hearthstones:5", "keep", "x"),
                                    ("shipped:unnamed:hearthstones:6", "accept", "x"),
                                    ("shipped:bogus:hearthstones:6", "keep", "x"),
                                    ("shipped:unfit:ignore:6", "keep", "x"),
                                    ("hearthstones:5", "accept", ""), ("hearthstones:5", "accept", "a\nb")):
            with self.assertRaises(SystemExit, msg=key):
                seeds.set_ruling({}, key, ruling, reason)

    def test_status_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertEqual(seeds.status_line("9.9", seeds.bundles(root, "retail")), "NEW 9.9 (no bundle yet)")
            b = root / "2026-01-02-retail"
            b.mkdir()
            (b / "candidates.json").write_text(json.dumps({"build": "9.8"}))
            self.assertEqual(seeds.status_line("9.8", seeds.bundles(root, "retail")),
                             "CURRENT 9.8 (2026-01-02-retail)")
            self.assertTrue(seeds.status_line("9.9", seeds.bundles(root, "retail")).startswith("NEW 9.9 (last ruled 9.8"))

    def test_rulings_path_per_flavor(self):
        self.assertEqual(seeds.rulings_path("retail").name, "retail_rulings.json")
        self.assertEqual(seeds.rulings_path("forever").name, "forever_rulings.json")


class TestApply(Workspace):
    def test_apply_refuses_while_unruled(self):
        with self.assertRaises(SystemExit):
            self.apply(self.doc(), {})
        self.assertEqual(self.seed.read_bytes(), SEED.encode("utf-8"))

    def test_apply_inserts_in_order_removes_keeps_crlf_and_is_idempotent(self):
        doc = self.doc()
        rulings = {k: {"ruling": "reject", "reason": "x"} for k in seeds.all_keys(doc)}
        rulings["hearthstones:700010"] = {"ruling": "accept", "reason": "a toy"}
        rulings["hearthstones:700011"] = {"ruling": "accept", "reason": "an item"}
        for f in doc["flags"]:
            rulings[f["key"]] = {"ruling": "keep", "reason": "x"}
        rulings["shipped:unnamed:hearthstones:950000"] = {"ruling": "remove", "reason": "gone"}
        changes = self.apply(doc, rulings)
        self.assertEqual(len(changes), 3)
        text = self.seed.read_bytes().decode("utf-8")
        self.assertNotIn("\n", text.replace("\r\n", ""), "every terminator stays CRLF")
        rows = [r["id"] for r in seeds.read_hearthstones(self.seed)]
        self.assertEqual(rows, [8690, 222695, 171253, 700001, 700003, 700010, 700011, 900001])
        self.assertIn("    700010,   -- Toy Hearthstone\r\n", text)
        self.assertTrue(text.startswith("local _, NS = ...\r\n-- header\r\n"))
        before = self.seed.read_bytes()
        self.assertEqual(self.apply(doc, rulings), [])
        self.assertEqual(self.seed.read_bytes(), before)
        self.assertEqual(self.ignore.read_bytes(), IGNORE.encode("utf-8"), "no ignore removal, no write")


class TestBuffs(Workspace):
    def test_buff_rule(self):
        derived = seeds.derive_buffs(self.facts, "retail")
        self.assertEqual(sorted(derived), [15366, 22888, 460940, 700202, 1229741])
        self.assertNotIn(700203, derived, "a catalog name with no aura effect is not derived")
        self.assertEqual(derived[460940], ["catalog: world: the head turn-in, Stormwind", "auras 34"],
                         "an area aura (Effect 35) counts")
        self.assertEqual(sorted(seeds.derive_buffs(self.facts, "forever")), sorted(derived))

    def test_buff_sentinel_gate_is_per_flavor(self):
        self.facts.spell_names.pop(1229741)
        self.assertIn(15366, seeds.derive_buffs(self.facts, "retail"), "Retail's gate does not need Camp Benefits")
        with self.assertRaises(SystemExit) as err:
            seeds.derive_buffs(self.facts, "forever")
        self.assertIn("1229741", str(err.exception))

    def test_wellfed_rule(self):
        self.assertEqual(sorted(seeds.derive_wellfed(self.facts)), [19705, 700200],
                         "Hearty Well Fed yes, Well Fed Bunny Report no")
        self.facts.auras.pop(19705)
        with self.assertRaises(SystemExit):
            seeds.derive_wellfed(self.facts)

    def test_food_rule(self):
        self.assertEqual(seeds.food_counts(self.facts), [{"class": 0, "subclass": 5, "items": 2},
                                                         {"class": 0, "subclass": 8, "items": 1},
                                                         {"class": 7, "subclass": 8, "items": 1}])
        self.assertEqual(seeds.derive_food(self.facts), {5: ["2 of the 3 Consumable items that use "
                                                             "Food/Drink/Refreshment/Food & Drink"]})
        self.facts.eating = {}
        with self.assertRaises(SystemExit):
            seeds.derive_food(self.facts)

    def test_read_buffs_per_client(self):
        retail = seeds.read_buffs(self.buffs, "Retail")
        self.assertEqual([r["id"] for r in retail["buffs"]], [15366, 22888, 700203, 950001])
        self.assertEqual(retail["wellfed"], [{"id": 19705, "name": ""}])
        self.assertEqual(retail["food"], [{"id": 5, "name": ""}])
        forever = seeds.read_buffs(self.buffs, "Forever")
        self.assertEqual((forever["buffs"], forever["wellfed"], forever["food"]),
                         ([{"id": 1229741, "name": "Camp Benefits"}], [], [{"id": 8, "name": ""}]))

    def test_buff_findings(self):
        doc = self.doc()
        self.assertEqual([c["key"] for c in doc["candidates"] if c["list"] in seeds.BUFF_LISTS],
                         ["buffs:460940", "buffs:700202", "buffs:1229741", "wellfed:700200"])
        self.assertEqual(sorted(f["key"] for f in doc["flags"] if f["list"] in seeds.BUFF_LISTS),
                         ["shipped:renamed:buffs:22888", "shipped:unfit:buffs:700203", "shipped:unnamed:buffs:950001"])
        self.assertEqual(doc["food"][0], {"class": 0, "subclass": 5, "items": 2})
        forever = self.doc("forever")
        self.assertEqual([c["key"] for c in forever["candidates"] if c["list"] == "food"], ["food:5"])
        self.assertEqual([f["key"] for f in forever["flags"] if f["list"] == "food"], ["shipped:unfit:food:8"])
        self.assertIn("## Food and drink", seeds.diff_md(forever))

    def _ruled(self, doc, accept=(), remove=()):
        rulings = {k: {"ruling": "reject", "reason": "x"} for k in seeds.all_keys(doc)}
        for f in doc["flags"]:
            rulings[f["key"]] = {"ruling": "keep", "reason": "x"}
        for key in accept:
            rulings[key] = {"ruling": "accept", "reason": "x"}
        for key in remove:
            rulings[key] = {"ruling": "remove", "reason": "x"}
        return rulings

    def test_apply_buffs_inserts_removes_and_keeps_the_other_client(self):
        doc = self.doc()
        rulings = self._ruled(doc, ("buffs:460940", "wellfed:700200"), ("shipped:unnamed:buffs:950001",))
        changes = self.apply(doc, rulings)
        self.assertEqual(changes, ["buffs Retail: -950001", "buffs Retail: +460940 Might of Stormwind",
                                   "wellfed Retail: +700200 Hearty Well Fed"])
        text = self.buffs.read_bytes().decode("utf-8")
        self.assertIn("            460940,   -- Might of Stormwind\r\n            700203,", text)
        self.assertIn("            19705,\r\n            700200,\r\n        },", text, "a Well Fed row has no name")
        self.assertNotIn("950001", text)
        self.assertTrue(text.endswith(BUFFS[BUFFS.index("    Forever = {"):]), "Forever's block is untouched")
        self.assertNotIn("\n", text.replace("\r\n", ""), "every terminator stays CRLF")
        self.assertEqual(self.apply(doc, rulings), [], "a second apply changes nothing")

    def test_apply_buffs_into_an_empty_list_and_the_food_subclass(self):
        doc = self.doc("forever")
        rulings = self._ruled(doc, ("buffs:460940", "food:5"), ("shipped:unfit:food:8",))
        changes = self.apply(doc, rulings)
        self.assertEqual(changes, ["food Forever: 8 -> 5", "buffs Forever: +460940 Might of Stormwind"])
        forever = seeds.read_buffs(self.buffs, "Forever")
        self.assertEqual(([r["id"] for r in forever["buffs"]], forever["food"]),
                         ([460940, 1229741], [{"id": 5, "name": ""}]))
        self.assertEqual(seeds.read_buffs(self.buffs, "Retail")["food"], [{"id": 5, "name": ""}])
        self.assertTrue(self.buffs.read_bytes().decode("utf-8").startswith(BUFFS[:BUFFS.index("    Forever = {")]),
                        "Retail's block is untouched")
        self.assertEqual([f["key"] for f in self.doc("forever")["flags"] if f["list"] == "food"], [],
                         "5 is now shipped")

    def test_apply_refuses_a_food_removal_with_no_replacement(self):
        doc = self.doc("forever")
        rulings = self._ruled(doc, remove=("shipped:unfit:food:8",))
        with self.assertRaises(SystemExit):
            self.apply(doc, rulings)
        self.assertEqual(self.buffs.read_bytes(), BUFFS.encode("utf-8"))


class TestRepo(unittest.TestCase):
    def test_shipped_files_parse(self):
        rows = seeds.read_hearthstones(seeds.HEARTH_FILE)
        ids = [r["id"] for r in rows]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(ids[:3], [8690, 222695, 171253])
        for client in ("Retail", "Forever"):
            seed = seeds.read_ignore(seeds.IGNORE_FILE, client)
            for row in seeds.ignore_rows(seed):
                self.assertTrue(row["name"], "the header names ignore seed %d" % row["id"])

    def test_shipped_buffs_match_the_rulings(self):
        """The gate (CL-13a): each client's shipped BuffSeeds ids are exactly its flavor's accepted
        candidates less its removed flags, every one is derived by the newest bundle, and a buff
        row's comment is its name there."""
        for flavor, info in seeds.FLAVORS.items():
            rulings = seeds.load_rulings(seeds.rulings_path(flavor))
            shipped = seeds.read_buffs(seeds.BUFF_FILE, info["client"])
            doc = seeds.load_doc(seeds.bundles(seeds.RESEARCH, flavor)[-1])
            for lst in seeds.BUFF_LISTS:
                ruled = {}
                for key, r in rulings.items():
                    m = seeds.KEY.match(key)
                    if m.group("list") == lst:
                        ruled.setdefault(r["ruling"], set()).add(int(m.group("id")))
                ids = [row["id"] for row in shipped[lst]]
                self.assertEqual(len(ids), len(set(ids)), "%s %s: no id twice" % (flavor, lst))
                self.assertEqual(set(ids), ruled.get("accept", set()) - ruled.get("remove", set()),
                                 "%s %s: shipped == accepted - removed" % (flavor, lst))
                self.assertEqual(ids, sorted(ids), "%s %s: ascending, as apply writes" % (flavor, lst))
                derived = {d["id"]: d["name"] for d in doc["derived"][lst]}
                for row in shipped[lst]:
                    self.assertIn(row["id"], derived, "%s %s: %d derived" % (flavor, lst, row["id"]))
                    if lst == "buffs":
                        self.assertEqual(row["name"], derived[row["id"]], "%s buff %d's comment" % (flavor, row["id"]))

    def test_newest_bundles_are_fully_ruled(self):
        for flavor in seeds.FLAVORS:
            found = seeds.bundles(seeds.RESEARCH, flavor)
            if not found:
                continue
            doc = seeds.load_doc(found[-1])
            self.assertEqual(seeds.unruled_keys(doc, seeds.load_rulings(seeds.rulings_path(flavor))), [], flavor)


if __name__ == "__main__":
    unittest.main()
