#!/usr/bin/env bash
# ask-local — LM Studio OpenAI 호환 API 호출 래퍼
#
# 용법:
#   ask-local "프롬프트 내용"
#   echo "긴 프롬프트" | ask-local
#   ask-local -m qwen3-8b "모델 명시 호출"
#   ask-local -s "코딩 전용 시스템 프롬프트" "실제 요청"
#
# 환경변수:
#   LM_STUDIO_URL    (기본 http://localhost:1234/v1)
#   LM_STUDIO_MODEL  (기본 qwen2.5-coder-14b-instruct)
#   LM_STUDIO_TEMP   (기본 0.2)
#   LM_STUDIO_MAX    (기본 2048)

set -euo pipefail

URL="${LM_STUDIO_URL:-http://localhost:1234/v1}"
MODEL="${LM_STUDIO_MODEL:-qwen2.5-coder-14b-instruct}"
TEMP="${LM_STUDIO_TEMP:-0.2}"
MAX_TOKENS="${LM_STUDIO_MAX:-2048}"
SYSTEM=""

# jq 필수
command -v jq >/dev/null || { echo "error: jq 필요 (brew install jq)" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model)  MODEL="$2"; shift 2 ;;
    -s|--system) SYSTEM="$2"; shift 2 ;;
    -t|--temp)   TEMP="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) break ;;
  esac
done

# stdin 또는 인자에서 프롬프트 수집
if [[ $# -gt 0 ]]; then
  PROMPT="$*"
elif [[ ! -t 0 ]]; then
  PROMPT="$(cat)"
else
  echo "error: 프롬프트가 필요합니다 (인자 또는 stdin)" >&2
  exit 1
fi

# 메시지 배열 구성
if [[ -n "$SYSTEM" ]]; then
  MESSAGES=$(jq -n --arg sys "$SYSTEM" --arg usr "$PROMPT" \
    '[{role:"system",content:$sys},{role:"user",content:$usr}]')
else
  MESSAGES=$(jq -n --arg usr "$PROMPT" '[{role:"user",content:$usr}]')
fi

PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --argjson messages "$MESSAGES" \
  --argjson temp "$TEMP" \
  --argjson max "$MAX_TOKENS" \
  '{model:$model, messages:$messages, temperature:$temp, max_tokens:$max, stream:false}')

# 서버 헬스 체크
if ! curl -sf -m 3 "${URL%/v1}/v1/models" >/dev/null 2>&1; then
  echo "error: LM Studio 서버에 연결할 수 없습니다 ($URL)" >&2
  echo "       LM Studio를 실행하고 Local Server를 시작하세요." >&2
  exit 2
fi

# 호출 및 응답 추출
RESPONSE=$(curl -sf -m 120 "$URL/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD") || {
  echo "error: API 호출 실패" >&2
  exit 3
}

echo "$RESPONSE" | jq -r '.choices[0].message.content // .error.message // "(빈 응답)"'
