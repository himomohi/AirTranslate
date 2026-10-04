"""잘못된 요청 연결과 손상된 계측 로그의 회귀를 확인한다."""

import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "summarize_latency_trace.py"
SPEC = importlib.util.spec_from_file_location("summarize_latency_trace", SCRIPT)
TRACE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TRACE)


def event(stage, uptime=10, **values):
    return {"stage": stage, "uptime": uptime, **values}


class LatencyTraceTests(unittest.TestCase):
    def test_failed_then_successful_same_line_length_is_not_mispaired(self):
        summary = TRACE.summarize([
            event("translation.queued", 9, id="request-1", characters=8),
            event("translation.start", 10, id="request-1", characters=8, queue_ms=1000),
            event("translation.failed", 10.3, id="request-1", characters=8),
            event("translation.queued", 10.9, id="request-2", characters=8),
            event("translation.start", 11, id="request-2", characters=8, queue_ms=100),
            event("translation.result", 11.2, id="request-2", characters=8, elapsed_ms=200),
        ])
        self.assertEqual(summary["translation_execution"]["p50_ms"], 200)
        self.assertEqual(summary["translation_execution"]["count"], 1)
        self.assertEqual(summary["translation_requests"]["failed"], 1)
        self.assertEqual(summary["translation_requests"]["completed"], 1)
        self.assertEqual(summary["translation_queue"]["count"], 2)
        self.assertEqual(summary["trace_format"], "v2")

    def test_legacy_failed_request_cannot_inflate_next_success(self):
        summary = TRACE.summarize([
            event("translation.start", 10, id="line", characters=8),
            event("translation.start", 11, id="line", characters=8),
            event("translation.result", 11.2, id="line", characters=8),
        ])
        self.assertEqual(summary["trace_format"], "legacy")
        self.assertEqual(summary["translation_execution"]["count"], 0)
        self.assertEqual(summary["translation_requests"]["legacy_events"], 3)
        self.assertEqual(summary["translation_requests"]["total"], 0)

    def test_out_of_order_terminal_uses_direct_duration(self):
        events = [
            event("translation.result", 11.2, id="r", elapsed_ms=200),
            event("translation.start", 11, id="r", queue_ms=100),
            event("translation.queued", 10.9, id="r"),
        ]
        summary = TRACE.summarize(events)
        ordered = TRACE.summarize(list(reversed(events)))
        self.assertEqual(summary["translation_execution"], ordered["translation_execution"])
        self.assertEqual(summary["translation_requests"], ordered["translation_requests"])
        self.assertEqual(summary["translation_execution"]["p50_ms"], 200)
        self.assertEqual(summary["translation_queue"]["p50_ms"], 100)

    def test_cancelled_superseded_and_incomplete_are_counted_per_request(self):
        summary = TRACE.summarize([
            event("translation.queued", id="cancelled"),
            event("translation.cancelled", id="cancelled"),
            event("translation.queued", id="superseded"),
            event("translation.superseded", id="superseded"),
            event("translation.queued", id="pending"),
            event("translation.start", id="running", queue_ms=0),
        ])
        requests = summary["translation_requests"]
        self.assertEqual(requests["total"], 4)
        self.assertEqual(requests["cancelled"], 1)
        self.assertEqual(requests["superseded"], 1)
        self.assertEqual(requests["incomplete"], 2)
        self.assertEqual(requests["completed"], 0)

    def test_mixed_legacy_translation_events_remain_unmeasured(self):
        summary = TRACE.summarize([
            event("translation.start", 1, id="old", characters=8),
            event("translation.result", 4, id="old", characters=8),
            event("translation.result", 4, id="new", characters=8, elapsed_ms=30),
        ])
        self.assertEqual(summary["trace_format"], "mixed")
        self.assertEqual(summary["translation_execution"]["p50_ms"], 30)
        self.assertEqual(summary["translation_requests"]["legacy_events"], 2)
        self.assertEqual(summary["translation_requests"]["terminal_without_start"], 1)

    def test_dispatch_uses_direct_measurement_only_for_mixed_logs(self):
        summary = TRACE.summarize([
            event("speech.result", 1, characters=8),
            event("speech.received", 1.1, characters=8, dispatch_ms=3),
            event("speech.result", 2, characters=8),
            event("speech.received", 2.1, characters=8),
        ])
        dispatch = summary["speech_dispatch"]
        self.assertEqual(dispatch["count"], 1)
        self.assertEqual(dispatch["p50_ms"], 3)
        self.assertEqual(dispatch["legacy_missing_events"], 1)

    def test_invalid_capture_values_are_excluded_with_reasons(self):
        summary = TRACE.summarize([
            event("speech.audio", 10, capture_time=9.5, duration=0.25),
            event("speech.audio", 10, capture_time=10, duration=0.25),
            event("speech.audio", 10, capture_time=float("nan"), duration=0.25),
            event("speech.audio", 10, capture_time=9, duration=float("inf")),
            event("speech.audio", 10, duration=0.25),
            event("speech.audio", 10, capture_time=[], duration=0.25),
            event("speech.audio", 10, capture_time=9, duration=-1),
        ])
        capture = summary["capture_callback_delay"]
        self.assertEqual(capture["count"], 1)
        self.assertEqual(capture["p50_ms"], 250)
        self.assertEqual(capture["excluded"], {
            "negative": 2, "non_finite": 2, "missing": 1, "non_numeric": 1,
        })

    def test_cross_session_first_events_are_not_connected(self):
        for events in (
            [event("floating.source", 10), event("translation.apply", 10000, id="other-line")],
            [event("translation.apply", 10, id="other-line"), event("floating.source", 10000)],
        ):
            with self.subTest(events=events):
                summary = TRACE.summarize(events)
                self.assertIsNone(summary["first_source_to_translation_ms"])

    def test_duplicate_and_conflicting_terminals_do_not_bias_distribution(self):
        summary = TRACE.summarize([
            event("translation.result", id="duplicate", elapsed_ms=20),
            event("translation.result", id="duplicate", elapsed_ms=20),
            event("translation.result", id="conflict", elapsed_ms=30),
            event("translation.failed", id="conflict"),
            event("translation.start", id="starts", queue_ms=10),
            event("translation.start", id="starts", queue_ms=20),
        ])
        self.assertEqual(summary["translation_execution"]["count"], 0)
        self.assertEqual(summary["translation_execution"]["excluded"], {
            "duplicate_results": 1, "conflicting_terminal_states": 1,
        })
        self.assertEqual(summary["translation_queue"]["excluded"], {"duplicate_starts": 1})
        self.assertEqual(summary["translation_requests"]["ambiguous"], 1)
        self.assertEqual(summary["translation_requests"]["duplicate_stage_events"], 2)

    def test_invalid_measurements_and_missing_duration_never_use_timestamp_delta(self):
        summary = TRACE.summarize([
            event("translation.queued", 1, id="missing"),
            event("translation.start", 2, id="missing"),
            event("translation.result", 3, id="missing"),
            event("translation.result", id="negative", elapsed_ms=-5),
            event("translation.start", id="bool", queue_ms=True),
            event("speech.received", dispatch_ms=float("inf")),
            event("speech.received", dispatch_ms=None),
        ])
        self.assertEqual(summary["translation_execution"]["count"], 0)
        self.assertEqual(summary["translation_execution"]["excluded"], {"missing": 1, "negative": 1})
        self.assertEqual(summary["translation_queue"]["excluded"], {"missing": 1, "non_numeric": 1})
        self.assertEqual(summary["speech_dispatch"]["excluded"], {"non_finite": 1, "missing": 1})

    def test_malformed_json_shapes_and_invalid_ids_are_counted(self):
        lines = ["ignored\n", TRACE.PREFIX + "{broken\n"]
        for value in [
            [], None, event("speech.received", float("nan")),
            event("speech.received", True), event([], 10),
            event("translation.result", id=[], elapsed_ms=1),
            event("speech.received", dispatch_ms=5),
        ]:
            lines.append(TRACE.PREFIX + json.dumps(value) + "\n")
        summary = TRACE.read_trace(io.StringIO("".join(lines)))
        self.assertEqual(summary["input"], {
            "valid_events": 2, "invalid_events": 5,
            "malformed_json_lines": 1, "ignored_lines": 1,
        })
        self.assertEqual(summary["translation_requests"]["invalid_id_events"], 1)
        self.assertEqual(summary["speech_dispatch"]["p50_ms"], 5)

    def test_extreme_numbers_still_produce_finite_json(self):
        summary = TRACE.summarize([
            event("speech.received", dispatch_ms=10 ** 1000),
            event("speech.received", dispatch_ms=1e308),
            event("speech.received", dispatch_ms=1e308),
            event("speech.audio", 1e308, capture_time=0, duration=0),
            event("speech.received", 10 ** 1000, dispatch_ms=1),
        ])
        json.dumps(summary, allow_nan=False)
        self.assertEqual(summary["input"]["invalid_events"], 1)
        self.assertEqual(summary["speech_dispatch"]["excluded"], {"non_finite": 1})
        self.assertEqual(summary["capture_callback_delay"]["excluded"], {"non_finite": 1})

    def test_cli_skips_malformed_lines_without_traceback(self):
        with tempfile.TemporaryDirectory() as directory:
            trace = Path(directory) / "trace.log"
            trace.write_text(
                TRACE.PREFIX + "{broken\n" + TRACE.PREFIX
                + json.dumps(event("speech.received", dispatch_ms=4)) + "\n",
                encoding="utf-8",
            )
            result = subprocess.run([sys.executable, str(SCRIPT), str(trace)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)
        self.assertEqual(summary["input"]["malformed_json_lines"], 1)
        self.assertEqual(summary["speech_dispatch"]["p50_ms"], 4)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_reports_no_valid_events_and_missing_file_without_traceback(self):
        with tempfile.TemporaryDirectory() as directory:
            trace = Path(directory) / "trace.log"
            trace.write_text(TRACE.PREFIX + "null\n" + TRACE.PREFIX + "{broken\n", encoding="utf-8")
            invalid = subprocess.run([sys.executable, str(SCRIPT), str(trace)], capture_output=True, text=True)
            missing = subprocess.run([sys.executable, str(SCRIPT), str(trace.with_name("missing.log"))], capture_output=True, text=True)
        for result in (invalid, missing):
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Traceback", result.stderr)
        self.assertIn("JSON 오류 1개", invalid.stderr)
        self.assertIn("유효하지 않은 이벤트 1개", invalid.stderr)
        self.assertIn("측정 로그를 읽을 수 없습니다", missing.stderr)


if __name__ == "__main__":
    unittest.main()
