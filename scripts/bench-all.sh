#!/usr/bin/env bash
# bench-all — 3종 모델을 순차로 벤치마크하고 비교 리포트 생성
#
# 전제: LM Studio 서버 실행 중, 각 모델이 이미 다운로드됨
# 모델 ID는 `lms ls` 출력 기준

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODELS=(
  "qwen3-14b-instruct"
  "gemma-4-26b-a4b"
  "phi-4"
)

OUT_DIR="results/$(date +%Y-%m-%d)"
mkdir -p "$OUT_DIR"

echo "[bench-all] 시작 — ${#MODELS[@]}개 모델"
for M in "${MODELS[@]}"; do
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  모델: $M"
  echo "═══════════════════════════════════════════"
  if ./scripts/bench-run.sh "$M" "$OUT_DIR"; then
    echo "  ✓ $M 완료"
  else
    echo "  ✗ $M 실패 (다음으로 진행)"
  fi
done

echo ""
echo "[bench-all] 모든 벤치 완료. 결과: $OUT_DIR/"
ls -lh "$OUT_DIR/"

echo ""
echo "[bench-all] 요약 생성 중..."
python3 scripts/bench-summarize.py "$OUT_DIR" > "$OUT_DIR/summary.md"
echo "[bench-all] 요약: $OUT_DIR/summary.md"
