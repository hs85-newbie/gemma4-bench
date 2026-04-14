#!/usr/bin/env bash
# profile-coder — 로컬 LLM 을 CODER 프로파일로 전환
#
# 구성: Qwen2.5-Coder 14B (8.33 GB) + Qwen 3 8B (4.62 GB) = ~12.95 GB
# 용도: 코드 생성·테스트 작성·타입 정의 등 코딩 집중 세션
#
# 주의: Gemma 4 등 다른 모델은 먼저 언로드됨 (~5초)
# 전체 소요: ~25~35초 (unload + 2회 load)

set -euo pipefail
export PATH="$HOME/bin:$PATH"

MAIN_MODEL="${CODER_MAIN:-qwen/qwen2.5-coder-14b}"
SUB_MODEL="${CODER_SUB:-qwen/qwen3-8b}"
CONTEXT="${CODER_CONTEXT:-16384}"

echo "[profile] CODER 전환 시작"
echo "  메인: $MAIN_MODEL (context=$CONTEXT)"
echo "  서브: $SUB_MODEL"

if ! lms server status 2>/dev/null | grep -q "running"; then
  echo "error: LM Studio 서버가 실행 중이지 않습니다. 'lms server start' 후 재시도." >&2
  exit 1
fi

echo "[profile] 기존 모델 언로드 중..."
lms unload --all 2>&1 | tail -1

echo "[profile] 메인 로드 중..."
lms load "$MAIN_MODEL" --gpu max --context-length "$CONTEXT" -y 2>&1 | tail -2

echo "[profile] 서브 로드 중..."
lms load "$SUB_MODEL" --gpu max --context-length "$CONTEXT" -y 2>&1 | tail -2

echo ""
echo "[profile] CODER 전환 완료"
lms ps
