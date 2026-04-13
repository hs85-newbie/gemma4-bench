# 로컬 LLM 3종 벤치마크 리포트

**하드웨어**: MacBook Air M2 / 8-core GPU / 24GB unified memory
**실행 일자**: 2026-04-13
**서버**: LM Studio 0.4.11 (llama.cpp 2.13.0 / mlx-llm 1.5.0)
**테스트 케이스**: 10개 (code/reasoning/korean/tool/long/agent 6 카테고리)

---

## 대상 모델

| # | 모델 ID | 아키텍처 | 양자화 | 디스크 크기 | 비고 |
|---|---|---|---|---|---|
| A | `qwen/qwen3-14b` | Qwen 3 | MLX 4bit | 8.32 GB | 범용·툴 사용 대표 |
| B | `microsoft/phi-4` | Phi-3 기반 | MLX 4bit | 9.05 GB | 추론·수학 특화 |
| C | `unsloth/gemma-4-26b-a4b-it-gguf` | Gemma 4 MoE | GGUF Q4_K_M | 14.82 GB | MoE, 스윗스팟 후보 |

> **참고**: Gemma 4 공식 `google/gemma-4-26B-A4B-it` 리포는 HF 게이티드 라이선스로 `lms get` 자동 다운로드 실패. Unsloth GGUF 미러로 대체.

---

## 결과 요약

_결과 JSON: `results/2026-04-13/` 참조_

| 모델 | 평균 tok/s | 평균 레이턴시(s) | 피크 메모리(MB) | 승자 카테고리 |
|---|---:|---:|---:|---|
| Qwen 3 14B | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| Phi-4 14B | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| Gemma 4 26B A4B | _TBD_ | _TBD_ | _TBD_ | _TBD_ |

_상세 표는 `results/2026-04-13/summary.md` 에 자동 생성되며, 본 문서에 병합됩니다._

---

## 카테고리별 분석

### 코드 생성 (code-01, code-02)
_TBD_

### 추론 (reason-01, reason-02)
_TBD_

### 한국어 (ko-01, ko-02)
_TBD_

### 툴 사용 (tool-01, tool-02)
_TBD_

### 긴 컨텍스트 (long-01)
_TBD_

### 에이전트 계획 (agent-01)
_TBD_

---

## 최종 추천

### 바이브 코딩 메인 워커
_TBD_

### 빠른 서브 워커
_TBD_

### 에이전트 오케스트레이션 (멀티 에이전트 패턴 C)
_TBD_

---

## 관찰 및 한계

### 측정 주의사항
- M2 8-core GPU는 M2 Pro/Max 대비 GPU 코어 수가 적어 일반 "Apple Silicon tok/s" 수치보다 낮게 나옴
- 24GB 통합 메모리는 다른 앱(브라우저, IDE)과 공유되어 실제 가용 메모리는 16~18GB 수준
- 백그라운드 다운로드가 진행 중이었을 경우 tok/s에 경미한 영향 가능

### Gemma 4 26B A4B 특이사항
- MoE 구조: 활성 파라미터 ~4B, 총 26B
- GGUF 기준 14.82 GB → 24GB 메모리에서 로드는 가능
- 컨텍스트 길이 설정에 따라 KV 캐시 메모리 추가 소모

### MLX vs GGUF
- Qwen/Phi: MLX 포맷 (M2 Metal 최적화, 일반적으로 10~20% 빠름)
- Gemma: GGUF 포맷 (llama.cpp 기반, MLX 버전 부재 시 대체)
- 동일 조건 비교가 완벽하지 않음을 감안

---

## 재현 방법

```bash
cd ~/gemma4-bench

# LM Studio 서버 실행 전제
lms server start

# 단일 모델 벤치
./scripts/bench-run.sh qwen/qwen3-14b results/2026-04-13

# 3종 일괄 벤치 (bench-all.sh 의 MODELS 배열 편집 필요)
./scripts/bench-all.sh
```

결과는 `results/<date>/<model-id>.json` 에 케이스별 응답·레이턴시·tok/s 포함 저장.
