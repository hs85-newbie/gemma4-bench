#!/usr/bin/env bash
# profile-generalist — 로컬 LLM 을 GENERALIST 프로파일로 전환
#
# 구성: Gemma 4 26B A4B (14.82 GB) + Qwen 3 8B (4.62 GB) = ~19.44 GB
# 용도: 문서·번역·요약·보일러플레이트 등 범용 태스크 전반
#
# 주의: Qwen2.5-Coder 14B 등 기타 모델은 먼저 언로드됨 (~5초)
# 전체 소요: ~25~35초 (unload + 2회 load)

set -euo pipefail
export PATH="$HOME/bin:$PATH"

MAIN_MODEL="${GENERALIST_MAIN:-gemma-4-26b-a4b-it}"
SUB_MODEL="${GENERALIST_SUB:-qwen/qwen3-8b}"
CONTEXT="${GENERALIST_CONTEXT:-8192}"

echo "[profile] GENERALIST 전환 시작"
echo "  메인: $MAIN_MODEL (context=$CONTEXT)"
echo "  서브: $SUB_MODEL"

# 서버 헬스체크
if ! lms server status 2>/dev/null | grep -q "running"; then
  echo "error: LM Studio 서버가 실행 중이지 않습니다. 'lms server start' 후 재시도." >&2
  exit 1
fi

# 모든 모델 언로드
echo "[profile] 기존 모델 언로드 중..."
lms unload --all 2>&1 | tail -1

# 메인 모델 로드
echo "[profile] 메인 로드 중..."
lms load "$MAIN_MODEL" --gpu max --context-length "$CONTEXT" -y 2>&1 | tail -2

# 서브 모델 로드
echo "[profile] 서브 로드 중..."
lms load "$SUB_MODEL" --gpu max --context-length "$CONTEXT" -y 2>&1 | tail -2

echo ""
echo "[profile] GENERALIST 전환 완료"
lms ps
