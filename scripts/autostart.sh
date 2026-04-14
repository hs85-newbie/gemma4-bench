#!/usr/bin/env bash
# autostart — 로그인 시 자동 실행되는 GENERALIST 프로파일 로더
#
# 동작:
#   1) LM Studio 앱 데몬 기동 (이미 실행 중이면 스킵)
#   2) lms server 시작 (포트 1234, 이미 떠 있으면 스킵)
#   3) GENERALIST 프로파일 로드 (Gemma 4 + Qwen 3 8B)
#
# 멱등성 보장: 여러 번 실행해도 안전. 이미 로드된 모델은 재로드 안 함.
#
# 호출 경로:
#   - ~/Library/LaunchAgents/com.hs85-newbie.gemma4-bench.autostart.plist (로그인 시 자동)
#   - 수동: ~/gemma4-bench/scripts/autostart.sh

set -uo pipefail

# PATH 보강 (launchd는 최소 PATH 제공)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.lmstudio/bin:$HOME/bin:$PATH"

LOG_DIR="$HOME/gemma4-bench/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/autostart.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

log "━━━ autostart 시작 ━━━"

# 1) LM Studio 앱 데몬 기동
if ! pgrep -x "LM Studio" > /dev/null; then
  log "LM Studio 앱 기동 중..."
  open -g -a "LM Studio" || { log "error: LM Studio 실행 실패"; exit 1; }
  sleep 6
else
  log "LM Studio 앱 이미 실행 중"
fi

# 2) lms 가 응답할 때까지 대기 (최대 20초)
for i in 1 2 3 4 5 6 7 8 9 10; do
  if lms ls > /dev/null 2>&1; then
    log "lms CLI 응답 확인"
    break
  fi
  [ "$i" = 10 ] && { log "error: lms 데몬 응답 없음 (20초 타임아웃)"; exit 2; }
  sleep 2
done

# 3) 서버 상태 확인 및 시작
if lms server status 2>&1 | grep -q "running"; then
  log "LM Studio 서버 이미 실행 중"
else
  log "LM Studio 서버 시작 중..."
  lms server start || { log "error: 서버 시작 실패"; exit 3; }
fi

# 4) GENERALIST 프로파일 상태 확인
MAIN_MODEL="gemma-4-26b-a4b-it"
SUB_MODEL="qwen/qwen3-8b"
LOADED=$(lms ps 2>&1)

NEEDS_LOAD=0
if ! echo "$LOADED" | grep -q "$MAIN_MODEL"; then
  log "메인 모델($MAIN_MODEL) 미로드 → 로드 필요"
  NEEDS_LOAD=1
fi
if ! echo "$LOADED" | grep -q "qwen3-8b"; then
  log "서브 모델($SUB_MODEL) 미로드 → 로드 필요"
  NEEDS_LOAD=1
fi

if [ "$NEEDS_LOAD" = "1" ]; then
  log "GENERALIST 프로파일 로드 시작..."
  # 메인 모델 미로드 시 → 모든 모델 언로드 후 올바른 순서로 재로드
  # (LM Studio 메모리 가드레일이 부분 언로드 상태를 보수적으로 판단하기 때문)
  if ! echo "$LOADED" | grep -q "$MAIN_MODEL"; then
    log "  모든 모델 언로드 (가드레일 회피)"
    lms unload --all 2>&1 | tail -1 | tee -a "$LOG"
    sleep 1

    log "  메인 로드: $MAIN_MODEL"
    lms load "$MAIN_MODEL" --gpu max --context-length 8192 -y 2>&1 | tail -2 | tee -a "$LOG"

    log "  서브 로드: $SUB_MODEL"
    lms load "$SUB_MODEL" --gpu max --context-length 8192 -y 2>&1 | tail -2 | tee -a "$LOG"
  else
    # 메인은 있는데 서브만 없는 경우 → 서브만 추가 로드
    if ! echo "$LOADED" | grep -q "qwen3-8b"; then
      log "  서브 로드: $SUB_MODEL"
      lms load "$SUB_MODEL" --gpu max --context-length 8192 -y 2>&1 | tail -2 | tee -a "$LOG"
    fi
  fi
else
  log "GENERALIST 프로파일 이미 로드됨 — 스킵"
fi

log "현재 로드 상태:"
lms ps 2>&1 | tee -a "$LOG"
log "━━━ autostart 완료 ━━━"
