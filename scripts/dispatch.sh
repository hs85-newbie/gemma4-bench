#!/usr/bin/env bash
# dispatch — 작업 설명을 받아 티어(모델) 결정을 JSON으로 반환
#
# 우선순위:
#   1) ANTHROPIC_API_KEY 가 있으면 Claude Haiku 로 분류 (0.5s 수준)
#   2) 없으면 로컬 LLM (기본 gemma-4-26b-a4b-it) 로 폴백 (15~30s)
#
# Claude Max 구독자 안내:
#   Max 구독은 Claude Code 만 커버하고 API 는 별도 결제입니다.
#   API 키 없이도 로컬 폴백으로 동작하며, 실전에서 dispatch.sh 독립 사용은
#   드물고 Claude Code 세션 내에선 Opus 가 직접 디스패치하므로 무관합니다.
#
# 용법:
#   ./dispatch.sh "사용자 테이블에 deleted_at 컬럼 추가하고 soft delete 쿼리 수정"
#   echo "작업 설명" | ./dispatch.sh
#
# 출력(JSON):
#   {"category":"cross_file_refactor","tier":"T1","confidence":0.85,"reason":"..."}
#
# 환경변수:
#   ANTHROPIC_API_KEY    Claude Haiku 사용 시 필요
#   DISPATCHER_MODEL     로컬 폴백 모델 (기본 gemma-4-26b-a4b-it)
#   LM_STUDIO_URL        기본 http://localhost:1234/v1
#
# 주의: Qwen 3 계열을 디스패처로 쓰면 reasoning 모드 때문에 60초 이상
#       걸림. Gemma 4 (비 reasoning) 를 기본으로 사용하는 것이 훨씬 빠름.
#       Qwen 3 사용 시 max_tokens 는 자동 처리되지만 curl timeout 180s 필요.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_FILE="$ROOT/config/dispatcher-prompt.md"
[[ -f "$PROMPT_FILE" ]] || { echo "error: $PROMPT_FILE 없음" >&2; exit 1; }

# 작업 설명 수집
if [[ $# -gt 0 ]]; then
  TASK="$*"
elif [[ ! -t 0 ]]; then
  TASK="$(cat)"
else
  echo "usage: $0 \"작업 설명\"" >&2
  exit 1
fi

# 시스템 프롬프트 추출 (dispatcher-prompt.md 의 *첫 번째* ``` ... ``` 블록만)
SYSTEM=$(awk '
  /^```$/ {
    if (f == 1) { exit }        # 닫는 펜스 만나면 중단
    f = 1; next                  # 여는 펜스 만나면 캡처 시작
  }
  f { print }
' "$PROMPT_FILE")

if [[ -z "$SYSTEM" ]]; then
  echo "error: dispatcher-prompt.md 에서 시스템 프롬프트를 찾지 못함" >&2
  exit 2
fi

# JSON 추출 유틸 — 응답에서 첫 번째 {...} 블록만 깨끗하게 뽑기
extract_json() {
  python3 -c '
import sys, json
s = sys.stdin.read()
depth = 0
start = -1
for i, c in enumerate(s):
    if c == "{":
        if depth == 0:
            start = i
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0 and start >= 0:
            snippet = s[start:i+1]
            try:
                obj = json.loads(snippet)
                print(json.dumps(obj, ensure_ascii=False, indent=2))
            except Exception:
                print(snippet)
            break
'
}

# ─── Anthropic Claude Haiku 경로 ──────────────────
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  RESPONSE=$(curl -sf -m 30 https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg sys "$SYSTEM" \
      --arg task "$TASK" \
      '{
        model: "claude-haiku-4-5-20251001",
        max_tokens: 800,
        system: $sys,
        messages: [{role:"user", content:$task}]
      }')") || {
    echo "warn: Anthropic API 호출 실패, 로컬 폴백 시도" >&2
    RESPONSE=""
  }

  if [[ -n "$RESPONSE" ]]; then
    CONTENT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty')
    if [[ -n "$CONTENT" ]]; then
      echo "$CONTENT" | extract_json
      exit 0
    fi
  fi
fi

# ─── 로컬 LLM 폴백 경로 ──────────────────────────
URL="${LM_STUDIO_URL:-http://localhost:1234/v1}"
MODEL="${DISPATCHER_MODEL:-gemma-4-26b-a4b-it}"

if ! curl -sf -m 3 "$URL/models" >/dev/null 2>&1; then
  echo "error: Anthropic API key 없고 LM Studio 서버도 응답 없음" >&2
  echo "       ANTHROPIC_API_KEY 를 설정하거나 'lms server start' 후 재시도." >&2
  exit 3
fi

PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --arg sys "$SYSTEM" \
  --arg task "$TASK" \
  '{
    model: $model,
    messages: [
      {role:"system", content:$sys},
      {role:"user", content:$task}
    ],
    temperature: 0.1,
    max_tokens: 800,
    stream: false
  }')

RESPONSE=$(curl -sf -m 180 "$URL/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD") || {
  echo "error: 로컬 LLM 호출 실패" >&2
  exit 4
}

CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')
echo "$CONTENT" | extract_json
