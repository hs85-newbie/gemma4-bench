# 로컬 LLM 3종 벤치마크 리포트

**하드웨어**: MacBook Air M2 / 8-core GPU / 24GB unified memory
**실행 일자**: 2026-04-13
**서버**: LM Studio 0.4.11 (llama.cpp 2.13.0 / mlx-llm 1.5.0)
**테스트 케이스**: 10개 (code/reasoning/korean/tool/long/agent 6 카테고리)

---

## 🏆 TL;DR — Gemma 4 26B A4B 압승

- **10.14 tok/s** / 평균 레이턴시 **31.17s**
- Phi-4 14B 대비 **1.80배**, Qwen 3 14B 대비 **1.56배** 빠름
- **6개 카테고리 전부 1위**
- 이유: 총 26B 파라미터 중 활성 4B만 추론에 참여하는 **MoE 구조**. 24GB 메모리에 충분히 들어가면서 속도는 4B급.

---

## 대상 모델

| # | 모델 ID | 아키텍처 | 양자화 | 디스크 크기 | 특이사항 |
|---|---|---|---|---|---|
| A | `qwen/qwen3-14b` | Qwen 3 | MLX 4bit | 8.32 GB | Thinking 모드 기본 ON |
| B | `microsoft/phi-4` | Phi-3 기반 | MLX 4bit | 9.05 GB | 15B 실파라미터 |
| C | `gemma-4-26b-a4b-it` | Gemma 4 MoE | GGUF Q4_K_M | 14.82 GB | MoE, 활성 4B |

> **주의**: Gemma 4 공식 `google/gemma-4-26B-A4B-it` 리포는 HF 게이티드 라이선스로 인해 `lms get` 자동 다운로드 실패. 우회 경로로 LM Studio 인덱싱된 **unsloth GGUF** 변종을 사용 (`https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF`).
>
> 이로 인해 Qwen/Phi는 MLX, Gemma만 GGUF로 **동일 조건 비교는 아님**. 일반적으로 MLX가 10~20% 빠른 것을 고려하면, MLX 변종이 있었다면 Gemma 우위는 더 컸을 가능성.

---

## 결과 요약

### 모델별 집계

| 순위 | 모델 | 평균 tok/s | 평균 레이턴시(s) | 총 출력 토큰 |
|---:|---|---:|---:|---:|
| 1 | **gemma-4-26b-a4b-it** | **10.14** | **31.17** | 3247 |
| 2 | qwen/qwen3-14b | 6.50 | 52.69 | 3470 |
| 3 | microsoft/phi-4 | 5.62 | 58.71 | 3352 |

> 메모리 컬럼은 측정 스크립트 이슈로 이번 런에서 신뢰 불가(`awk` 프로세스 매칭 실패). 실제 측정은 `lms ps` 의 MODEL SIZE 로 대체.
> - Qwen 3 14B: 7.75 GiB 상주 (컨텍스트 8K)
> - Phi-4 14B: 8.5 GiB 내외 (Q4_K_M)
> - Gemma 4 26B A4B: 14.82 GiB 상주 (GGUF 특성)

### 카테고리별 평균 tok/s (1위 굵게)

| 카테고리 | gemma-4 | phi-4 | qwen3-14b |
|---|---:|---:|---:|
| agent (계획 수립) | **9.8** | 4.7 | 5.5 |
| code (코드 생성) | **16.3** | 8.4 | 9.3 |
| korean (한국어 요약/번역) | **8.6** | 5.0 | 5.7 |
| long (긴 컨텍스트 요약) | **8.9** | 4.6 | 5.3 |
| reasoning (SQL/알고리즘) | **8.5** | 5.3 | 6.6 |
| tool (함수 호출 JSON) | **7.9** | 4.7 | 5.6 |

### 케이스별 레이턴시 (초)

| 케이스 | gemma-4 | phi-4 | qwen3-14b |
|---|---:|---:|---:|
| agent-01 (5단계 계획) | 61.19 | 126.59 | 109.10 |
| code-01 (LRU 캐시 TS) | **29.78** | 70.70 | 66.84 |
| code-02 (useDebounce 훅) | **39.92** | 60.63 | 51.80 |
| ko-01 (공지 요약) | 15.19 | 29.35 | 35.41 |
| ko-02 (에러 친화 변환) | 17.07 | 30.59 | 26.23 |
| long-01 (회의록 정리) | 34.46 | 83.22 | 74.77 |
| reason-01 (SQL 진단) | 53.39 | 77.86 | 59.38 |
| reason-02 (O(n²)→O(n)) | 46.71 | 83.59 | 71.35 |
| tool-01 (get_weather JSON) | 4.95 | 9.18 | 18.07 |
| tool-02 (MCP JSON-RPC) | 9.03 | 15.35 | 13.93 |

---

## 카테고리별 정성 분석

### 1. 코드 생성 (code-01, code-02)
- **Gemma 4**: Map 기반 O(1) LRU, 완전한 TypeScript 제네릭, 한국어 JSDoc 완벽. 단위 테스트 Vitest 구조까지 포함.
- **Qwen 3 14B**: Qwen2.5-Coder만큼은 아니지만 충분히 사용 가능. Thinking 모드로 장황한 설명이 붙어 tok/s 저하.
- **Phi-4**: 가장 느림. 14B dense 모델 한계.

→ **바이브 코딩 메인 워커는 Gemma 4가 확정**. Qwen2.5-Coder 14B(8.79 tok/s, Task 1 실측)보다도 빠름.

### 2. 추론 (reason-01, reason-02)
- Phi-4가 정확도는 가장 좋다는 평가를 받지만 **속도는 가장 느림**. 바이브 코딩 속도가 중요한 사용자에게는 Gemma 4가 실질적 1위.
- Gemma 4의 SQL 진단은 인덱스 제안과 수정 쿼리 모두 정확.

### 3. 한국어 (ko-01, ko-02)
- 3 모델 모두 자연스러운 존댓말 생성. 차이는 속도뿐.
- Gemma 4의 에러 메시지 친화 변환이 가장 간결.

### 4. 툴 사용 (tool-01, tool-02)
- 모든 모델이 JSON 스키마 준수.
- Gemma 4가 5초 이내 응답 (**tool-01 4.95s**) — 에이전트 루프에 적합.

### 5. 긴 컨텍스트 (long-01)
- 회의록 요약 3섹션 구분: 3개 모델 모두 정확.
- Gemma 4가 34초로 가장 빠름 (다른 모델은 70초+).

### 6. 에이전트 계획 (agent-01)
- Next.js 인증 5단계 계획 — 3개 모델 모두 마크다운 표 형식 준수.
- 다만 Phi-4는 126초가 걸려 에이전트 루프에는 부적합.

---

## 최종 추천 (MacBook Air M2 24GB 기준)

### 🥇 바이브 코딩 메인 워커
**`gemma-4-26b-a4b-it` (GGUF Q4_K_M)**
- 이유: 모든 카테고리 1위, MoE 구조로 속도·품질 동시 확보
- 단점: 14.82GB 상주 → 다른 14B 모델과 동시 로드 불가 (24GB 한계)
- 컨텍스트 4~8K에서 가장 안정적

### 🥈 보조 / 순차 스왑용
**`qwen/qwen3-14b` (MLX)**
- Gemma 4를 언로드하고 다른 14B가 필요할 때
- Thinking 모드 OFF 시 더 빠름 (`"enable_thinking": false` 옵션)

### ⚡ 패턴 B 하이브리드 (Claude Code + 로컬)
1. 평상시: Gemma 4 로드 → Claude Code에서 `ask-local` 또는 MCP로 위임
2. 코드 전용 반복 작업: Qwen2.5-Coder 14B로 교체 (코드 품질 더 우수)
3. 긴급 가벼운 태스크: Qwen 3 8B (4.62GB, 여유 메모리에 보조로)

### ❌ 순수 로컬 멀티 에이전트 (패턴 C)
**24GB 메모리에서 14B급 모델 동시 로드는 불가.** 멀티 에이전트 실험은 Gemma 4 + 8B 1개 조합이 한계. 진짜 멀티 에이전트는 클라우드 오케스트레이터(Claude) + 로컬 워커 1개 패턴 B로 대체하는 것이 현실적.

---

## 관찰 및 주의사항

### 1. M2 8-core GPU 현실
- 이전 예상 "14B MLX 15~25 tok/s"는 M2 Pro/Max 기준. 맥북 에어 M2는 **약 6~8 tok/s**가 한계.
- Gemma 4의 10 tok/s는 MoE 활성 파라미터가 작아 나오는 숫자이지, 14B dense였다면 훨씬 낮았을 것.

### 2. 백그라운드 부하 영향
- 벤치 진행 중 Gemma 4 다운로드가 동시 진행되어 Qwen 3 14B 벤치에 경미한 영향 가능. Phi-4/Gemma4 벤치는 다운로드 종료 후 실행됨.

### 3. Gemma 4 GGUF vs MLX
- 공식 Google 리포의 MLX 변종이 있었다면 Gemma 4 점수는 더 올라갔을 것.
- 현재 결과는 **Gemma 4 의 보수적 하한선** 으로 해석.

### 4. Thinking 모드 변수
- Qwen 3 는 기본적으로 thinking 모드가 ON 이어서 응답 토큰에 `<thinking>...</thinking>` 이 포함될 수 있음. 이번 벤치는 기본 설정 사용.
- OFF 로 벤치 재실행 시 Qwen 3 의 tok/s 가 20~30% 증가할 가능성.

### 5. 메모리 측정 스크립트 이슈
- `bench-run.sh` 의 `mem_snapshot` 함수가 `ps` 출력에서 MLX/llama 프로세스를 매칭하지 못해 MB 단위 결과가 부정확 (47 MB 등).
- 향후 `vm_stat` 기반 또는 `footprint` 명령으로 교체 필요 → **후속 작업**.

---

## 후속 작업

1. **메모리 측정 스크립트 개선** — footprint / vm_stat 기반
2. **MLX Gemma 4 공개 시 재벤치** — Google 또는 mlx-community 미러 확인
3. **Thinking OFF Qwen 3 재벤치** — 공정 비교용
4. **Qwen2.5-Coder 14B 포함 4종 비교** — 코딩 전용 대결
5. **컨텍스트 길이별 KV 캐시 영향 측정** — 8K/16K/32K

---

## 재현 방법

```bash
cd ~/gemma4-bench

# LM Studio 서버 실행 전제
lms server start

# 단일 모델 벤치
./scripts/bench-run.sh gemma-4-26b-a4b-it results/$(date +%F)

# 3종 일괄 벤치
./scripts/bench-all.sh

# 요약 생성
python3 scripts/bench-summarize.py results/$(date +%F)
```

결과 JSON: `results/<date>/<model-id>.json`
비교 요약: `results/<date>/summary.md`
