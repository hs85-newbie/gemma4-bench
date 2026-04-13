#!/usr/bin/env bash
# bench-run — 단일 모델을 로드하고 테스트 케이스 전체를 실행, 결과를 JSON으로 저장
#
# 용법:
#   ./bench-run.sh <model-id> [output-dir]
#
# 예:
#   ./bench-run.sh qwen3-14b-instruct results/2026-04-13
#
# 동작:
#   1) lms load <model-id> 로 로드
#   2) testcases/cases.json 의 각 케이스를 API 호출
#   3) 응답/레이턴시/tokens-per-sec/메모리 기록
#   4) lms unload 로 해제
#   5) 결과: <output-dir>/<model-id>.json

set -euo pipefail

MODEL="${1:-}"
OUT_DIR="${2:-results/$(date +%Y-%m-%d)}"

if [[ -z "$MODEL" ]]; then
  echo "usage: $0 <model-id> [output-dir]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASES="$ROOT/testcases/cases.json"
URL="${LM_STUDIO_URL:-http://localhost:1234/v1}"

[[ -f "$CASES" ]] || { echo "error: $CASES 없음" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq 필요" >&2; exit 3; }
command -v python3 >/dev/null || { echo "error: python3 필요" >&2; exit 3; }

mkdir -p "$OUT_DIR"
RESULT_FILE="$OUT_DIR/${MODEL//\//_}.json"
TMP_RESULTS=$(mktemp)
trap 'rm -f "$TMP_RESULTS"' EXIT

echo "[bench] 모델 로드: $MODEL"
lms load "$MODEL" --gpu max --context-length 8192 -y 2>&1 | tail -3 || {
  echo "error: 모델 로드 실패" >&2
  exit 4
}

# 메모리 측정 (MB 단위, RSS 기준)
mem_snapshot() {
  ps -A -o rss,command 2>/dev/null \
    | awk '/LM Studio Helper|llama|mlx/ {sum+=$1} END {printf "%d", sum/1024}'
}

MEM_BEFORE=$(mem_snapshot)
echo "[bench] 로드 후 메모리: ${MEM_BEFORE} MB"

# 각 케이스 실행
CASE_COUNT=$(jq '. | length' "$CASES")
echo "[bench] $CASE_COUNT 개 케이스 실행 시작"

echo "[]" > "$TMP_RESULTS"

for i in $(seq 0 $((CASE_COUNT - 1))); do
  CASE=$(jq ".[$i]" "$CASES")
  ID=$(echo "$CASE" | jq -r '.id')
  CATEGORY=$(echo "$CASE" | jq -r '.category')
  TITLE=$(echo "$CASE" | jq -r '.title')
  PROMPT=$(echo "$CASE" | jq -r '.prompt')
  MAX_TOKENS=$(echo "$CASE" | jq -r '.expected_tokens // 1024')

  echo "  [$((i+1))/$CASE_COUNT] $ID ($CATEGORY) — $TITLE"

  PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "$PROMPT" \
    --argjson max "$MAX_TOKENS" \
    '{model:$model, messages:[{role:"user",content:$prompt}], temperature:0.2, max_tokens:$max, stream:false}')

  START=$(python3 -c "import time; print(time.time())")
  RESPONSE=$(curl -sf -m 300 "$URL/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" || echo '{"error":"request failed"}')
  END=$(python3 -c "import time; print(time.time())")

  LATENCY=$(python3 -c "print(round($END - $START, 2))")
  CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // ""')
  PROMPT_TOK=$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens // 0')
  COMPLETION_TOK=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens // 0')
  TPS=$(python3 -c "print(round($COMPLETION_TOK / $LATENCY, 2) if $LATENCY > 0 else 0)")

  RESULT=$(jq -n \
    --arg id "$ID" --arg category "$CATEGORY" --arg title "$TITLE" \
    --arg content "$CONTENT" \
    --argjson latency "$LATENCY" \
    --argjson prompt_tok "$PROMPT_TOK" \
    --argjson completion_tok "$COMPLETION_TOK" \
    --argjson tps "$TPS" \
    '{id:$id,category:$category,title:$title,latency_sec:$latency,prompt_tokens:$prompt_tok,completion_tokens:$completion_tok,tokens_per_sec:$tps,content:$content}')

  jq --argjson r "$RESULT" '. += [$r]' "$TMP_RESULTS" > "$TMP_RESULTS.new" && mv "$TMP_RESULTS.new" "$TMP_RESULTS"

  echo "      → ${LATENCY}s, ${COMPLETION_TOK} tok, ${TPS} tok/s"
done

MEM_AFTER=$(mem_snapshot)
echo "[bench] 최종 메모리: ${MEM_AFTER} MB"

# 집계
jq -n \
  --arg model "$MODEL" \
  --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson mem_before "$MEM_BEFORE" \
  --argjson mem_after "$MEM_AFTER" \
  --slurpfile results "$TMP_RESULTS" \
  '{
    model: $model,
    run_at: $date,
    memory_mb: {before: $mem_before, after: $mem_after},
    aggregate: {
      total_cases: ($results[0] | length),
      avg_tps: ([$results[0][].tokens_per_sec] | add / length),
      avg_latency: ([$results[0][].latency_sec] | add / length),
      total_completion_tokens: ([$results[0][].completion_tokens] | add)
    },
    cases: $results[0]
  }' > "$RESULT_FILE"

echo "[bench] 결과 저장: $RESULT_FILE"

echo "[bench] 모델 언로드"
lms unload "$MODEL" 2>&1 | tail -2 || true

echo "[bench] 완료"
