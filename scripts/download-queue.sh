#!/usr/bin/env bash
# download-queue — 벤치 대상 모델을 순차 다운로드 (병렬하면 회선 공유로 더 느림)
#
# 각 모델 완료 후 다음으로. 실패는 기록만 하고 계속.

set -uo pipefail
export PATH="$HOME/bin:$PATH"

LOG_DIR="/tmp/lms-downloads"
mkdir -p "$LOG_DIR"
QUEUE_LOG="$LOG_DIR/queue.log"

MODELS=(
  "qwen/qwen3-14b"
  "microsoft/phi-4"
  "google/gemma-4-26B-A4B-it"
  "qwen/qwen3-8b"
)

# HF 기준 확인된 Gemma 4 리포지토리: google/gemma-4-26B-A4B-it (MoE),
# google/gemma-4-E4B-it, google/gemma-4-31B-it. 24GB M2 스윗스팟은 26B A4B.

echo "[$(date +%T)] 다운로드 큐 시작: ${#MODELS[@]}개" | tee "$QUEUE_LOG"

for M in "${MODELS[@]}"; do
  NAME=$(echo "$M" | tr '/' '_')
  LOG="$LOG_DIR/${NAME}.log"
  echo "[$(date +%T)] ▶ $M → $LOG" | tee -a "$QUEUE_LOG"
  if lms get -y "$M" > "$LOG" 2>&1; then
    echo "[$(date +%T)] ✓ $M 완료" | tee -a "$QUEUE_LOG"
  else
    echo "[$(date +%T)] ✗ $M 실패 (계속 진행)" | tee -a "$QUEUE_LOG"
  fi
done

echo "[$(date +%T)] 큐 완료" | tee -a "$QUEUE_LOG"
lms ls | tee -a "$QUEUE_LOG"
