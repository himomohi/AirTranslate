#!/usr/bin/env python3
"""명시적으로 수집한 숫자 전용 AirTranslate 로그를 요약한다."""

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path


PREFIX = "AIRTRANSLATE_LATENCY "
REQUEST_STAGES = {
    "translation.queued", "translation.start", "translation.result",
    "translation.failed", "translation.cancelled", "translation.superseded",
}
TERMINAL_STATES = {
    "translation.result": "completed",
    "translation.failed": "failed",
    "translation.cancelled": "cancelled",
    "translation.superseded": "superseded",
}


def numeric_issue(value):
    if value is None:
        return "missing"
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return "non_numeric"
    try:
        if not math.isfinite(value):
            return "non_finite"
    except OverflowError:
        return "non_finite"
    return "negative" if value < 0 else None


def distribution(values, excluded=None):
    exclusions = Counter(excluded or {})
    accepted = []
    for value in values:
        issue = numeric_issue(value)
        if issue:
            exclusions[issue] += 1
        else:
            accepted.append(value)
    accepted.sort()
    result = {"count": len(accepted), "excluded": dict(exclusions)}
    if accepted:
        middle = len(accepted) // 2
        median = accepted[middle]
        if len(accepted) % 2 == 0:
            lower = accepted[middle - 1]
            median = lower + (median - lower) / 2
        result.update({
            "p50_ms": round(median, 3),
            "p95_ms": round(accepted[math.ceil(len(accepted) * 0.95) - 1], 3),
            "max_ms": round(accepted[-1], 3),
        })
    return result


def is_request_contract_marker(event):
    stage = event["stage"]
    return (
        stage in REQUEST_STAGES - {"translation.start", "translation.result"}
        or (stage == "translation.start" and "queue_ms" in event)
        or (stage == "translation.result" and "elapsed_ms" in event)
    )


def request_id(event):
    value = event.get("id")
    return value if isinstance(value, str) and value.strip() else None


def summarize(events, *, malformed_json_lines=0, ignored_lines=0):
    valid_events = []
    invalid_events = 0
    for event in events:
        if (not isinstance(event, dict)
                or not isinstance(event.get("stage"), str)
                or not event["stage"].strip()
                or numeric_issue(event.get("uptime"))):
            invalid_events += 1
        else:
            valid_events.append(event)
    events = valid_events
    stages = Counter(event["stage"] for event in events)
    contract_ids = {
        request_id(event) for event in events
        if is_request_contract_marker(event) and request_id(event) is not None
    }
    requests = defaultdict(lambda: defaultdict(list))
    legacy_events = contract_events = invalid_id_events = 0
    dispatch, capture_delay = [], []
    capture_excluded = Counter()
    legacy_dispatch = 0
    for event in events:
        stage = event["stage"]
        if stage == "speech.received":
            if "dispatch_ms" not in event:
                legacy_dispatch += 1
            else:
                dispatch.append(event["dispatch_ms"])
        elif stage == "speech.audio":
            issue = numeric_issue(event.get("capture_time")) or numeric_issue(event.get("duration"))
            if issue:
                capture_excluded[issue] += 1
            else:
                capture_delay.append((event["uptime"] - event["capture_time"] - event["duration"]) * 1000)
        if stage in REQUEST_STAGES:
            identity = request_id(event)
            if identity in contract_ids or is_request_contract_marker(event):
                contract_events += 1
                if identity is None:
                    invalid_id_events += 1
                else:
                    requests[identity][stage].append(event)
            else:
                legacy_events += 1

    states = Counter({state: 0 for state in (*TERMINAL_STATES.values(), "incomplete", "ambiguous")})
    queue, execution = [], []
    queue_excluded, execution_excluded = Counter(), Counter()
    duplicates = terminal_without_start = 0
    for recorded in requests.values():
        duplicates += sum(len(items) - 1 for items in recorded.values())
        terminals = [stage for stage in TERMINAL_STATES if stage in recorded]
        if len(terminals) > 1:
            states["ambiguous"] += 1
            execution_excluded["conflicting_terminal_states"] += 1
        elif terminals:
            terminal = terminals[0]
            states[TERMINAL_STATES[terminal]] += 1
            if terminal == "translation.result":
                results = recorded[terminal]
                if len(results) == 1:
                    execution.append(results[0].get("elapsed_ms"))
                else:
                    execution_excluded["duplicate_results"] += 1
        else:
            states["incomplete"] += 1
        starts = recorded.get("translation.start", [])
        if terminals and not starts:
            terminal_without_start += 1
        if len(starts) == 1:
            queue.append(starts[0].get("queue_ms"))
        elif starts:
            queue_excluded["duplicate_starts"] += 1

    trace_format = "mixed" if contract_events and legacy_events else "v2" if contract_events else "legacy"
    speech_dispatch = distribution(dispatch)
    speech_dispatch["legacy_missing_events"] = legacy_dispatch
    return {
        "schema": "airtranslate.latency-summary.v2",
        "trace_format": trace_format,
        "input": {
            "valid_events": len(events), "invalid_events": invalid_events,
            "malformed_json_lines": malformed_json_lines, "ignored_lines": ignored_lines,
        },
        "stages": dict(stages),
        "speech_dispatch": speech_dispatch,
        "translation_queue": distribution(queue, queue_excluded),
        "translation_execution": distribution(execution, execution_excluded),
        "translation_requests": {
            "total": len(requests), **dict(states),
            "terminal_without_start": terminal_without_start,
            "duplicate_stage_events": duplicates,
            "legacy_events": legacy_events,
            "invalid_id_events": invalid_id_events,
        },
        "capture_callback_delay": distribution(capture_delay, capture_excluded),
        "first_source_to_translation_ms": None,
        "final_results": sum(event.get("final") == 1 for event in events if event["stage"] == "speech.result"),
        "board_rewrites": {
            stage: (sum(event.get("rewrite") == 1 for event in events if event["stage"] == stage)
                    if stages[stage] else None)
            for stage in ("board.source", "board.translation")
        },
        "boundaries": [
            "발화 시작부터의 지연이나 화면의 실제 렌더링 완료 시간을 측정하지 않는다.",
            "번역은 요청별 고유 id와 직접 기록한 queue_ms·elapsed_ms만 사용한다. 기존 줄 id·글자 수·이벤트 간격으로 추정하지 않는다.",
            "translation_execution은 성공 요청의 실행 시간이며 큐 대기·debounce·전처리 시간은 translation_queue로 별도 집계한다.",
            "요청 상태는 로그에 남은 이벤트만 집계한다. 잘린 로그와 충돌·중복 이벤트는 전체 세션 완료율의 근거가 아니다.",
            "원문·번역의 줄과 세션을 연결할 수 없어 first_source_to_translation_ms는 미측정(null)이다.",
            "speech_dispatch는 직접 기록된 dispatch_ms만 사용하며 legacy_missing_events는 미측정이다.",
            "capture_callback_delay는 PCM 변환 후 시점과 PTS+duration의 차이이다. 시간 기준 호환성을 별도로 확인해야 하며 제외 값은 excluded에 표시한다.",
            "동일한 음성 파일, 설정, 빌드 구성과 계측 조건으로 수집한 로그끼리 비교한다.",
        ],
    }


def read_trace(stream):
    events = []
    malformed_json_lines = ignored_lines = 0
    for line in stream:
        if not line.startswith(PREFIX):
            ignored_lines += 1
            continue
        try:
            events.append(json.loads(line[len(PREFIX):]))
        except (ValueError, RecursionError):
            malformed_json_lines += 1
    return summarize(events, malformed_json_lines=malformed_json_lines, ignored_lines=ignored_lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    args = parser.parse_args()
    try:
        with args.trace.open(encoding="utf-8", errors="replace") as stream:
            summary = read_trace(stream)
    except OSError:
        parser.error("측정 로그를 읽을 수 없습니다. 파일 경로와 읽기 권한을 확인하세요.")
    if not summary["input"]["valid_events"]:
        parser.error(
            "유효한 측정 이벤트가 없습니다. AIRTRANSLATE_LATENCY_TRACE=1로 수집하세요. "
            f"JSON 오류 {summary['input']['malformed_json_lines']}개, 유효하지 않은 이벤트 {summary['input']['invalid_events']}개."
        )
    print(json.dumps(summary, ensure_ascii=False, allow_nan=False, indent=2))


if __name__ == "__main__":
    main()
