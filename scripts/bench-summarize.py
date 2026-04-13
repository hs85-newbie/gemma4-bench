#!/usr/bin/env python3
"""
bench-summarize — results 디렉토리의 모델별 JSON을 읽어 비교 마크다운 생성.

용법: python3 bench-summarize.py <results-dir>
"""
import json
import sys
from pathlib import Path


def load_results(results_dir: Path) -> list[dict]:
    """디렉토리 내 모든 *.json 파일을 읽어 리스트 반환."""
    runs = []
    for path in sorted(results_dir.glob("*.json")):
        if path.name.startswith("summary"):
            continue
        try:
            runs.append(json.loads(path.read_text()))
        except json.JSONDecodeError as e:
            print(f"warn: {path.name} 파싱 실패: {e}", file=sys.stderr)
    return runs


def format_model_table(runs: list[dict]) -> str:
    """모델별 집계 표."""
    lines = [
        "## 모델별 집계",
        "",
        "| 모델 | 평균 tok/s | 평균 레이턴시(s) | 총 출력 토큰 | 메모리(MB) |",
        "|---|---:|---:|---:|---:|",
    ]
    for run in runs:
        agg = run.get("aggregate", {})
        mem = run.get("memory_mb", {})
        lines.append(
            f"| {run['model']} | "
            f"{agg.get('avg_tps', 0):.1f} | "
            f"{agg.get('avg_latency', 0):.2f} | "
            f"{agg.get('total_completion_tokens', 0)} | "
            f"{mem.get('after', 0)} |"
        )
    return "\n".join(lines)


def format_category_table(runs: list[dict]) -> str:
    """카테고리별 평균 tok/s 비교."""
    if not runs:
        return ""
    categories = sorted({c["category"] for run in runs for c in run.get("cases", [])})
    models = [run["model"] for run in runs]

    header = "| 카테고리 | " + " | ".join(models) + " |"
    sep = "|---|" + "---:|" * len(models)
    lines = ["## 카테고리별 평균 tok/s", "", header, sep]

    for cat in categories:
        row = [cat]
        for run in runs:
            vals = [c["tokens_per_sec"] for c in run.get("cases", []) if c["category"] == cat]
            avg = sum(vals) / len(vals) if vals else 0
            row.append(f"{avg:.1f}")
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def format_per_case_latency(runs: list[dict]) -> str:
    """케이스별 레이턴시 비교 표."""
    if not runs:
        return ""
    case_ids = sorted({c["id"] for run in runs for c in run.get("cases", [])})
    models = [run["model"] for run in runs]

    header = "| 케이스 | " + " | ".join(models) + " |"
    sep = "|---|" + "---:|" * len(models)
    lines = ["## 케이스별 레이턴시(s)", "", header, sep]

    for cid in case_ids:
        row = [cid]
        for run in runs:
            case = next((c for c in run.get("cases", []) if c["id"] == cid), None)
            row.append(f"{case['latency_sec']:.2f}" if case else "-")
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def pick_winner(runs: list[dict]) -> str:
    """가장 균형 잡힌 모델 선정 (간단 스코어)."""
    if not runs:
        return ""
    # tok/s 는 높을수록 좋음, 메모리는 낮을수록 좋음
    scored = []
    max_tps = max(r["aggregate"]["avg_tps"] for r in runs) or 1
    min_mem = min(r["memory_mb"]["after"] for r in runs if r["memory_mb"]["after"] > 0) or 1
    for r in runs:
        tps_norm = r["aggregate"]["avg_tps"] / max_tps
        mem_norm = min_mem / (r["memory_mb"]["after"] or 1)
        score = tps_norm * 0.6 + mem_norm * 0.4
        scored.append((score, r["model"]))
    scored.sort(reverse=True)
    return "\n".join(
        [
            "## 종합 스코어 (속도 60% + 메모리 효율 40%)",
            "",
            "| 순위 | 모델 | 스코어 |",
            "|---|---|---:|",
            *[f"| {i+1} | {m} | {s:.3f} |" for i, (s, m) in enumerate(scored)],
        ]
    )


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: bench-summarize.py <results-dir>", file=sys.stderr)
        return 1

    results_dir = Path(sys.argv[1])
    if not results_dir.is_dir():
        print(f"error: {results_dir} 디렉토리 없음", file=sys.stderr)
        return 2

    runs = load_results(results_dir)
    if not runs:
        print("error: 결과 JSON이 없습니다", file=sys.stderr)
        return 3

    print("# 로컬 LLM 벤치마크 결과")
    print("")
    print(f"실행 디렉토리: `{results_dir}`")
    print(f"모델 수: {len(runs)}")
    print("")
    print(format_model_table(runs))
    print("")
    print(format_category_table(runs))
    print("")
    print(format_per_case_latency(runs))
    print("")
    print(pick_winner(runs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
