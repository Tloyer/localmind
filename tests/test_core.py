import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

TEMP_DATA = tempfile.TemporaryDirectory(prefix="localmind-test-")
os.environ["LOCALMIND_DATA_DIR"] = TEMP_DATA.name
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from localmind import server


class CoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        server.init_db()

    def setUp(self):
        with server.conn() as c:
            c.execute("DELETE FROM activities")
            c.execute("DELETE FROM captures")
            c.execute("DELETE FROM reports")
            c.execute("DELETE FROM memory_observations")
            c.execute("DELETE FROM hourly_memories")

    def test_interval_union_prevents_double_counting(self):
        self.assertEqual(server.union_length([(0,10),(5,20),(30,40)]),30)

    def test_timeline_merges_overlapping_heartbeats_without_adding_twice(self):
        day=server.dt.date.today().isoformat(); start,end=server.day_bounds(day)
        with server.conn() as c:
            c.execute("INSERT INTO activities(fingerprint,start,end,app,window_title,source) VALUES(?,?,?,?,?,?)",("beat-1",start+600,start+900,"Editor","project.py","window"))
            c.execute("INSERT INTO activities(fingerprint,start,end,app,window_title,source) VALUES(?,?,?,?,?,?)",("beat-2",start+800,start+1000,"Editor","project.py","window"))
        rows=server.timeline(day)
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0]["duration_seconds"],400)
        self.assertEqual(len(rows[0]["evidence_ids"]),2)

    def test_idle_is_subtracted_from_active_usage(self):
        day="2026-10-15"
        start,end=server.day_bounds(day)
        with server.conn() as c:
            c.execute("INSERT INTO activities(fingerprint,start,end,app,source) VALUES(?,?,?,?,?)",("app",start+60,start+3600,"Editor","window"))
            c.execute("INSERT INTO activities(fingerprint,start,end,status,source) VALUES(?,?,?,?,?)",("afk",start+600,start+1200,"afk","afk"))
        result=server.time_stats(day)
        self.assertEqual(result["active_seconds"],2940)
        self.assertEqual(result["idle_seconds"],600)

    def test_sensitive_filter_and_subdomains(self):
        settings=server.load_settings()
        self.assertTrue(server.is_excluded("Google Chrome","Private browsing","",settings))
        self.assertTrue(server.is_excluded("Chrome","bank portal","secure.example.org",settings))
        settings["excluded_domains"]=["example.com"]
        self.assertTrue(server.is_excluded("Chrome","Dashboard","a.example.com",settings))
        self.assertFalse(server.is_excluded("Chrome","Dashboard","example.net",settings))

    def test_ollama_only_accepts_loopback(self):
        self.assertEqual(server.local_url("http://127.0.0.1:11434/"),"http://127.0.0.1:11434")
        for url in ("https://127.0.0.1:11434","http://192.168.1.2:11434","http://example.com"):
            with self.assertRaises(ValueError): server.local_url(url)

    def test_daily_report_requires_evidence_ids(self):
        self.assertIn("additionalProperties",server.REPORT_SCHEMA)
        self.assertEqual(server.local_url(server.load_settings()["ollama_url"]),"http://127.0.0.1:11434")

    def test_memory_observation_deduplicates_and_discards_temporary_frame(self):
        settings={**server.load_settings(),"capture_enabled":True,"memory_enabled":True,"vision_interval_seconds":300}
        server.VISION_LAST_TS=server.time.monotonic()
        def fake_helper(*args,**kwargs):
            if args[0]=="capture":
                Path(args[1]).write_bytes(b"temporary-frame")
                return {"sha256":"same-frame","ocrText":"LocalMind task view","bytes":15}
            return {}
        with patch.object(server,"load_settings",return_value=settings), \
             patch.object(server,"eligible_capture_context",return_value=({"id":None},{"app":"Demo","title":"Task view"},"")), \
             patch.object(server,"helper_call",side_effect=fake_helper):
            first=server.collect_memory_observation()
            second=server.collect_memory_observation()
        self.assertTrue(first["observed"])
        self.assertEqual(second["skipped"],"画面文字与上下文未变化")
        with server.conn() as c:
            self.assertEqual(c.execute("SELECT count(*) FROM memory_observations").fetchone()[0],1)
        self.assertEqual(list(server.VISION_TMP.iterdir()),[])

    def test_hourly_memory_exports_daily_markdown_and_removes_raw_observations(self):
        day=server.dt.date.today().isoformat(); start,end=server.day_bounds(day)
        with server.conn() as c:
            c.execute("INSERT INTO memory_observations(observed_at,app,window_title,ocr_text,vision_text) VALUES(?,?,?,?,?)",
                      (start+3600,"Demo","Task view","Edited project plan","Reviewed a task board"))
        with patch.object(server,"ollama_generate",return_value={"memory":"09:00 左右在 Demo 中编辑项目计划，并查看任务看板。"}):
            server.generate_hourly_memory(day,1)
        with server.conn() as c:
            memory=c.execute("SELECT status,content FROM hourly_memories WHERE day=? AND hour=1",(day,)).fetchone()
            self.assertEqual(c.execute("SELECT count(*) FROM memory_observations").fetchone()[0],0)
        self.assertEqual(memory["status"],"ready")
        self.assertIn("09:00 左右",(server.MEMORIES/f"{day}.md").read_text(encoding="utf-8"))

    def test_report_generation_keeps_only_cited_claims(self):
        day=server.dt.date.today().isoformat()
        start,end=server.day_bounds(day)
        with server.conn() as c:
            c.execute("INSERT INTO activities(fingerprint,start,end,app,window_title,source) VALUES(?,?,?,?,?,?)",("real-evidence",start+600,start+1800,"VS Code","LocalMind server.py","window"))
            evidence_id=c.execute("SELECT id FROM activities WHERE fingerprint='real-evidence'").fetchone()[0]
        def fake_model(prompt,schema,settings,timeout=180):
            if schema is server.CLAIMS_SCHEMA:
                return {"claims":[{"text":"查看了 LocalMind 服务代码记录。","evidence_ids":[evidence_id],"certainty":"fact"}]}
            return {"overview":[{"text":"今天有 VS Code 活动记录。","evidence_ids":[evidence_id],"certainty":"fact"}],"work_review":[],"learning":[],"ideas":[],"tomorrow_suggestions":[]}
        with patch.object(server,"ollama_generate",side_effect=fake_model):
            server.generate_report(day)
        report=server.report_for(day)
        self.assertEqual(report["status"],"ready")
        self.assertEqual(report["report"]["sections"]["overview"][0]["evidence_ids"],[evidence_id])
        self.assertTrue(report["report"]["time_allocation"]["timeline"])

    def test_activitywatch_import_is_read_only_and_deduplicated(self):
        stamp=server.dt.datetime.now().astimezone().replace(microsecond=0).isoformat()
        buckets={"aw-watcher-window_host":{"type":"currentwindow"},"aw-watcher-web_host":{"type":"web"}}
        def fake_request(url,method="GET",body=None,timeout=3):
            if url.rstrip("/").endswith("/api/0/buckets"): return buckets
            if "aw-watcher-web_host" in url:
                return [{"timestamp":stamp,"duration":30,"data":{"title":"Local docs","url":"https://docs.example.org","incognito":False}}]
            return [{"timestamp":stamp,"duration":30,"data":{"app":"Google Chrome","title":"Local docs"}}]
        with patch.object(server,"request_json",side_effect=fake_request):
            first=server.import_aw_events()
            second=server.import_aw_events()
        self.assertEqual(first["imported"],2)
        self.assertEqual(second["imported"],0)
        with server.conn() as c:
            rows=c.execute("SELECT source,url FROM activities ORDER BY source").fetchall()
        self.assertEqual({r["source"] for r in rows},{"window","web"})
        self.assertEqual(next(r["url"] for r in rows if r["source"]=="web"),"https://docs.example.org")

    def test_incognito_browser_activity_is_not_imported(self):
        stamp=server.dt.datetime.now().astimezone().replace(microsecond=0).isoformat()
        buckets={"aw-watcher-window_host":{"type":"currentwindow"},"aw-watcher-web_host":{"type":"web"}}
        def fake_request(url,method="GET",body=None,timeout=3):
            if url.rstrip("/").endswith("/api/0/buckets"): return buckets
            if "aw-watcher-web_host" in url:
                return [{"timestamp":stamp,"duration":30,"data":{"title":"Private page","url":"https://private.example","incognito":True}}]
            return [{"timestamp":stamp,"duration":30,"data":{"app":"Google Chrome","title":"Private page"}}]
        with patch.object(server,"request_json",side_effect=fake_request):
            server.import_aw_events()
        with server.conn() as c:
            count=c.execute("SELECT count(*) FROM activities").fetchone()[0]
        self.assertEqual(count,0)

    def test_expired_images_are_deleted_but_ocr_evidence_remains(self):
        image=Path(TEMP_DATA.name)/"old.jpg"; image.write_bytes(b"jpeg test bytes")
        with server.conn() as c:
            c.execute("INSERT INTO captures(captured_at,app,window_title,path,sha256,ocr_text) VALUES(?,?,?,?,?,?)",(server.now_ts()-8*86400,"Editor","notes",str(image),"old-hash","persistent OCR evidence"))
        self.assertEqual(server.cleanup_screenshots(),1)
        self.assertFalse(image.exists())
        with server.conn() as c:
            row=c.execute("SELECT path,ocr_text FROM captures WHERE sha256='old-hash'").fetchone()
        self.assertEqual(row["path"],"")
        self.assertEqual(row["ocr_text"],"persistent OCR evidence")


if __name__=="__main__":
    unittest.main()
