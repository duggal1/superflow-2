#!/usr/bin/env python3
"""Offline unit + fake-server tests for bench.py. Never loads a model.

Run: python3 tools/bench-s1/test_bench.py
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench  # noqa: E402


class FakeCompletionHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802 - stdlib API
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        body = json.dumps({
            "choices": [{"finish_reason": "stop", "message": {"content": "cleaned text"}}],
            "usage": {"prompt_tokens": 12, "completion_tokens": 6, "total_tokens": 18},
            "timings": {"predicted_n": 6, "predicted_ms": 100.0,
                        "predicted_per_second": 60.0},
        }).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_: Any) -> None:
        pass


class PureHelperTests(unittest.TestCase):
    def test_percentiles_known_values(self) -> None:
        values = list(range(1, 101))  # 1..100
        result = bench.percentiles(values)
        self.assertAlmostEqual(result["p50"], 50.5)
        self.assertAlmostEqual(result["p95"], 95.05)
        self.assertAlmostEqual(result["p99"], 99.01)
        self.assertEqual(result["min"], 1)
        self.assertEqual(result["max"], 100)
        self.assertAlmostEqual(result["mean"], 50.5)

    def test_percentiles_empty_and_single(self) -> None:
        self.assertEqual(bench.percentiles([]), {})
        single = bench.percentiles([7.0])
        self.assertEqual(single["p50"], 7.0)
        self.assertEqual(single["p95"], 7.0)
        self.assertEqual(single["p99"], 7.0)

    def test_prompt_contract_exact(self) -> None:
        messages = bench.build_messages("some raw transcript")
        self.assertEqual(len(messages), 2)
        self.assertEqual(messages[0], {"role": "system", "content": bench.SYSTEM_PROMPT})
        self.assertEqual(messages[1], {
            "role": "user",
            "content": bench.CONTROL_LINE + "\n" + "some raw transcript",
        })
        self.assertIn("output only the cleaned text", bench.SYSTEM_PROMPT)
        self.assertEqual(
            bench.CONTROL_LINE,
            "[Styling: semi-formal] [Structure: lists] [Context: general]",
        )

    def test_request_body_is_greedy_nonstreaming(self) -> None:
        body = bench.build_request_body("hi")
        self.assertEqual(body["temperature"], 0)
        self.assertFalse(body["stream"])
        self.assertEqual(body["max_tokens"], bench.DEFAULT_MAX_TOKENS)
        self.assertNotIn("<|im_start|>", json.dumps(body))  # Jinja handles the prefix

    def test_server_command_has_documented_flags(self) -> None:
        cmd = bench.server_command("llama-server", "/tmp/model.gguf", 9999)
        self.assertEqual(cmd[0], "llama-server")
        self.assertIn("-m", cmd)
        self.assertEqual(cmd[cmd.index("-m") + 1], "/tmp/model.gguf")
        self.assertIn("--jinja", cmd)
        self.assertIn("--chat-template-kwargs", cmd)
        self.assertEqual(cmd[cmd.index("--chat-template-kwargs") + 1],
                         '{"enable_thinking":false}')
        self.assertIn("--temp", cmd)
        self.assertEqual(cmd[cmd.index("--temp") + 1], "0")
        self.assertIn("-c", cmd)
        self.assertEqual(cmd[cmd.index("-c") + 1], "2048")
        self.assertIn("127.0.0.1", cmd)

    def test_extract_call_tokens_per_second(self) -> None:
        body = bench.build_request_body("abc def")
        payload = {
            "choices": [{"finish_reason": "length"}],
            "usage": {"prompt_tokens": 12, "completion_tokens": 6},
            "timings": {"predicted_per_second": 60.0},
        }
        call = bench._extract_call(body, payload, latency_ms=2000.0)
        self.assertEqual(call["prompt_tokens"], 12)
        self.assertEqual(call["completion_tokens"], 6)
        self.assertTrue(call["hit_token_cap"])
        self.assertAlmostEqual(call["e2e_output_tokens_per_s"], 3.0)
        self.assertEqual(call["server_decode_tokens_per_s"], 60.0)
        self.assertEqual(call["input_chars"], 7)

    def test_extract_call_without_timings(self) -> None:
        body = bench.build_request_body("abc")
        payload = {"choices": [{"finish_reason": "stop"}], "usage": {}}
        call = bench._extract_call(body, payload, latency_ms=100.0)
        self.assertIsNone(call["server_decode_tokens_per_s"])
        self.assertIsNone(call["e2e_output_tokens_per_s"])
        self.assertFalse(call["hit_token_cap"])


class BatchingTests(unittest.TestCase):
    def test_batch_size_is_clamped(self) -> None:
        with self.assertRaises(ValueError):
            bench.run_bench(["x"], lambda _: ({}, 1.0), batch_size=11)

    def test_total_cap_stops_early(self) -> None:
        ticks = {"n": 0}

        def clock() -> float:
            ticks["n"] += 1
            return float(ticks["n"])

        calls = 0

        def call(_: dict[str, Any]) -> tuple[dict[str, Any], float]:
            nonlocal calls
            calls += 1
            return ({"choices": [{"finish_reason": "stop"}],
                     "usage": {"prompt_tokens": 1, "completion_tokens": 1}}, 100.0)

        run = bench.run_bench(
            ["a", "b", "c", "d", "e"], call,
            batch_size=5, total_cap_s=2.5, time_fn=clock,
            sleep_fn=lambda _: None,
        )
        self.assertEqual(calls, 2)
        self.assertEqual(run["attempted"], 2)
        self.assertTrue(run["stopped_by_cap"])
        self.assertEqual(len(run["calls"]), 2)

    def test_error_is_recorded_and_run_continues(self) -> None:
        def call(_: dict[str, Any]) -> tuple[dict[str, Any], float]:
            raise TimeoutError("per-call cap")

        run = bench.run_bench(["a", "b"], call, batch_size=2,
                              time_fn=lambda: 0.0, sleep_fn=lambda _: None)
        self.assertEqual(len(run["errors"]), 2)
        self.assertEqual(run["calls"], [])
        self.assertEqual(bench.summarize(run)["status"], "EMPTY_NOT_MEASURED")

    def test_summarize_statuses(self) -> None:
        ok = {"calls": [{"latency_ms": 10.0, "e2e_output_tokens_per_s": 5.0,
                         "server_decode_tokens_per_s": None,
                         "prompt_tokens": 1, "completion_tokens": 1,
                         "hit_token_cap": False}],
              "errors": [], "attempted": 1, "stopped_by_cap": False,
              "elapsed_s": 0.1, "limits": {}}
        self.assertEqual(bench.summarize(ok)["status"], "MEASURED")
        partial = dict(ok, errors=[{"type": "TimeoutError", "message": "x"}])
        self.assertEqual(bench.summarize(partial)["status"], "PARTIAL")
        capped = dict(ok)
        capped["calls"] = [dict(ok["calls"][0], hit_token_cap=True)]
        self.assertEqual(bench.summarize(capped)["status"], "PARTIAL")


class OptInTests(unittest.TestCase):
    def test_missing_opt_in_refuses(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = bench.main([])
        self.assertEqual(code, 2)
        self.assertIn("REFUSING TO RUN", stderr.getvalue())

    def test_non_loopback_base_url_refuses(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = bench.main(["--i-opt-in", "--base-url", "http://example.com"])
        self.assertEqual(code, 2)
        self.assertIn("loopback", stderr.getvalue())


class FakeServerIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeCompletionHandler)
        cls.port = cls.server.server_port
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def test_post_completion_and_end_to_end_result(self) -> None:
        base_url = f"http://127.0.0.1:{self.port}"
        payload, latency = bench.post_completion(
            base_url, bench.build_request_body("offline synthetic text"))
        self.assertEqual(payload["usage"]["completion_tokens"], 6)
        self.assertGreaterEqual(latency, 0.0)

        run = bench.run_bench(["one", "two", "three"],
                              lambda body: bench.post_completion(base_url, body),
                              batch_size=2, total_cap_s=10.0)
        summary = bench.summarize(run)
        self.assertEqual(summary["status"], "MEASURED")
        self.assertEqual(summary["calls_succeeded"], 3)
        self.assertEqual(summary["calls_failed"], 0)
        self.assertEqual(summary["latency_ms"]["p50"],
                         bench.percentiles([c["latency_ms"] for c in run["calls"]])["p50"])

        result = {
            "schema": bench.RESULT_SCHEMA,
            "claim_scope": bench.CLAIM_SCOPE,
            "summary": summary,
            "run": run,
        }
        with tempfile.TemporaryDirectory() as tmp:
            path = bench.write_result(Path(tmp), result)
            data = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], bench.RESULT_SCHEMA)
        self.assertEqual(data["summary"]["status"], "MEASURED")
        self.assertIn("NOT a measurement of key-down", data["claim_scope"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
