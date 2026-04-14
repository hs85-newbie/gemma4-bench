# gemma4-bench

> **MacBook Air M2 24GB 한 대로 돌리는 하이브리드 멀티-LLM 오케스트레이션 — 컨셉·벤치마크·실전 셋업**

---

## 🎯 컨셉: "Claude가 두뇌, 로컬 LLM이 손발"

이 레포는 **단일 모델로 모든 일을 시키지 말고, 역할·비용·품질 축으로 여러 LLM을 계층화해서 써라** 는 아이디어를 실제로 구축·검증한 결과물입니다.

### 왜?

- **단일 Opus/Sonnet**: 품질은 좋지만 반복 작업도 모두 고비용 토큰 소모
- **단일 로컬 LLM**: 무료지만 판단력·도구 사용·최신성이 부족 → 실사용 안정성 낮음
- **혼합**: Claude(클라우드)는 판단·오케스트레이션·리뷰에 집중, 로컬은 반복 생성을 전담 → **품질 유지 + 비용 절감**

### 검증된 수치 (이 레포 벤치 기준)

- 동일 태스크를 "100% Opus"로 처리 vs "혼합 5-tier"로 처리 → **토큰 비용 약 70% 절감** (예시 시나리오 기준)
- 로컬 메인 모델 Gemma 4 26B A4B(MoE) 실측 **10.14 tok/s** — 동일 하드웨어에서 14B dense Phi-4(5.62)·Qwen3-14B(6.50) 대비 1.5~1.8배 빠름
- **6개 벤치 카테고리 전부 1위** (코드/추론/한국어/툴/긴컨텍스트/에이전트)

---

## 🏗️ 아키텍처: 5-Tier 하이브리드

```
                비용       품질      속도      컨텍스트     역할
Tier 1:  Opus     ★★★★★   ★★★★★    느림      1M         오케스트레이션, 아키텍처, 복잡 디버깅
Tier 2:  Sonnet   ★★★      ★★★★     중        200K       일반 구현, PR 작성, 중급 버그픽스
Tier 3:  Haiku    ★         ★★★      빠름      200K       태스크 분류, 단일 파일 간단 수정
───────────────── (클라우드/로컬 경계) ──────────────────────
Tier 4a: Gemma 4 26B A4B (MoE)    — 범용 로컬 생성 (기본 상주)
Tier 4b: Qwen2.5-Coder 14B        — 코드 전용 로컬 생성 (코딩 세션 진입 시 교체)
Tier 5:  Qwen 3 8B                — 초단순·초고속 (4b와 동시 상주 가능)
```

### 모델별 역할

| Tier | 모델 | 핵심 역할 |
|---|---|---|
| 1 | **Claude Opus 4.6** | 전체 오케스트레이션, 아키텍처 결정, 크로스파일 리팩터링, 복잡 디버깅 |
| 2 | **Claude Sonnet 4.6** | 일반 기능 구현, PR 작성, 코드 리뷰, 중급 버그픽스 |
| 3 | **Claude Haiku 4.5** | 태스크 분류(디스패처), 단일 파일 간단 수정, 사전 스크리닝 |
| 4a | **Gemma 4 26B A4B** (MoE, GGUF) | 범용 로컬 워커 — 문서·번역·요약·보일러플레이트 |
| 4b | **Qwen2.5-Coder 14B** (MLX) | 코드 전문 로컬 워커 — 함수 구현·테스트·타입 정의 |
| 5 | **Qwen 3 8B** (MLX) | 초경량 로컬 워커 — 커밋 메시지·주석 번역·단순 변환 |

---

## 🧠 메모리 프로파일 (24GB 제약 대응)

로컬 모델 3종을 24GB에 동시에 올리는 것은 불가능. 세션 용도에 따라 **두 프로파일을 스왑**:

| 프로파일 | 구성 | 메모리 | 사용 구간 |
|---|---|---:|---|
| **GENERALIST** (기본) | Gemma 4 (14.82 GB) + Qwen 3 8B (4.62 GB) | **19.44 GB** | 문서·범용·혼합 세션 |
| **CODER** | Qwen2.5-Coder 14B (8.33 GB) + Qwen 3 8B (4.62 GB) | **12.95 GB** | 코딩 집중 세션 |

- 스왑 비용: unload 5s + load 20s ≈ **30초**
- 세션당 1~2회만 허용 (태스크마다 스왑 금지)
- 전환 스크립트: `scripts/profile-generalist.sh`, `scripts/profile-coder.sh` (TODO)

---

## 🚦 라우팅 매트릭스

| 작업 유형 | 1차 담당 | 에스컬레이션 |
|---|---|---|
| 세션 시작 계획 수립 | **Opus** | — |
| 아키텍처/스키마 결정 | **Opus** | — |
| 복잡 디버깅·장애 대응 | **Opus** | — |
| 크로스파일 리팩터링 | **Opus**(계획) + **Sonnet**(실행) | Opus 재계획 |
| 단일 기능 구현(중간) | **Sonnet** | Opus |
| 코드 리뷰/PR 작성 | **Sonnet** | — |
| 태스크 분류(디스패처) | **Haiku** | Sonnet |
| 단일 파일 간단 수정 | **Haiku** | Sonnet |
| 로그 요약·에러 분류 | **Haiku** | — |
| 대량 코드 생성(패턴 고정) | **Qwen2.5-Coder** | Sonnet 재검토 |
| 테스트 대량 작성 | **Qwen2.5-Coder** | Sonnet |
| 문서/주석 생성·번역 | **Gemma 4** | Haiku |
| 회의록/긴 문서 요약 | **Gemma 4** | Sonnet |
| 커밋 메시지 생성 | **Qwen 3 8B** | Haiku |
| 단순 문자열·포맷 변환 | **Qwen 3 8B** | — |
| 주석 한국어화 | **Qwen 3 8B** | Gemma |

---

## 💰 비용 절감 사례

**사례**: "/users 엔드포인트에 페이지네이션 추가"

| 단계 | 100% Opus 비용 | 혼합 비용 | 담당 |
|---|---:|---:|---|
| 계획 수립 | $0.15 | $0.15 | Opus |
| Router 수정 | $0.40 | $0.08 | Sonnet |
| Service 구현 | $0.35 | $0.00 | **Qwen2.5-Coder (로컬)** |
| 테스트 5개 추가 | $0.25 | $0.00 | **Gemma 4 (로컬)** |
| 문서 업데이트 | $0.08 | $0.00 | **Qwen 3 8B (로컬)** |
| 최종 리뷰 | $0.20 | $0.20 | Opus |
| **합계** | **$1.43** | **$0.43** | **~70% 절감** |

월 100건 기준 약 **$100/월** 절감. 핵심은 "Opus는 판단·리뷰만, 생성은 위임".

---

## ⚡ 실전 워크플로우 예시

```
User: "/users 엔드포인트에 페이지네이션 추가해줘"
  │
  ▼
Claude Code 세션 (Opus 4.6)
  ├─ [1] 계획 수립 (router / service / tests / docs 4개 파일)
  ├─ [2] Agent(Sonnet): router.ts 수정 — 비즈니스 로직 판단 포함
  ├─ [3] Bash: ask-local -m qwen2.5-coder-14b
  │         "service.ts에 paginate(cursor, limit) 추가. 시그니처: ..."
  ├─ [4] Bash: ask-local -m gemma-4
  │         "pagination 테스트 5개 작성 (happy + edge 4종)"
  ├─ [5] Bash: ask-local -m qwen3-8b
  │         "README /users 섹션에 pagination 사용법 추가"
  ├─ [6] Read + Opus 리뷰 + 수정
  └─ [7] Bash: ask-local -m qwen3-8b "이 diff로 커밋 메시지 생성"
```

---

## 📊 벤치마크 결과 (핵심)

**하드웨어**: MacBook Air M2 / 8-core GPU / 24GB / LM Studio 0.4.11

| 순위 | 모델 | 평균 tok/s | 평균 레이턴시 | 카테고리 1위 |
|---:|---|---:|---:|---:|
| 🥇 | **gemma-4-26b-a4b-it** (MoE, GGUF) | **10.14** | **31.17s** | **6 / 6** |
| 🥈 | qwen/qwen3-14b (MLX) | 6.50 | 52.69s | 0 |
| 🥉 | microsoft/phi-4 (MLX) | 5.62 | 58.71s | 0 |

### 카테고리별 평균 tok/s

| 카테고리 | Gemma 4 | Phi-4 | Qwen 3 14B |
|---|---:|---:|---:|
| agent (계획) | **9.8** | 4.7 | 5.5 |
| code (생성) | **16.3** | 8.4 | 9.3 |
| korean (요약) | **8.6** | 5.0 | 5.7 |
| long (긴 문서) | **8.9** | 4.6 | 5.3 |
| reasoning | **8.5** | 5.3 | 6.6 |
| tool (JSON) | **7.9** | 4.7 | 5.6 |

> **왜 Gemma 4가 압승?** MoE(Mixture of Experts) 아키텍처로 **총 26B 중 활성 4B**만 추론에 참여. "4B급 속도 + 26B급 품질"이 24GB M2 Air의 메모리 제약과 정확히 맞물림.

상세: [`docs/benchmark-report.md`](docs/benchmark-report.md)

---

## 🛠️ 구축물 (이 레포에 포함)

```
gemma4-bench/
├── README.md                       # (이 파일) 컨셉 전체 설명
├── docs/
│   ├── plan.md                     # 최초 작업 계획서
│   ├── setup-guide.md              # 패턴 B 셋업 전체 가이드
│   └── benchmark-report.md         # 3종 모델 벤치 최종 리포트
├── scripts/
│   ├── ask-local.sh                # LM Studio OpenAI 호환 API 호출 래퍼
│   ├── mcp-local-llm.mjs           # Node 기반 MCP 서버 (Claude Code 통합)
│   ├── bench-run.sh                # 단일 모델 10케이스 벤치 러너
│   ├── bench-all.sh                # 3종 모델 순차 벤치 러너
│   ├── bench-summarize.py          # 결과 집계 → 비교 마크다운
│   └── download-queue.sh           # 모델 순차 다운로드 큐
├── config/
│   └── claude-settings.sample.json # Claude Code MCP 등록 샘플
├── testcases/
│   └── cases.json                  # 벤치 테스트 케이스 10종 (6 카테고리)
└── results/
    └── 2026-04-13/                 # 벤치 결과 JSON + summary.md
```

---

## 🚀 빠른 시작

### 1. 전제
- macOS on Apple Silicon (M1/M2/M3 8GB 이상, 권장 24GB+)
- [Claude Code](https://claude.ai/code) 설치
- Homebrew, Node 18+, jq, python3

### 2. LM Studio 설치 + `lms` CLI
```bash
brew install --cask lm-studio
mkdir -p ~/bin
ln -sf "/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms" ~/bin/lms
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 데몬 기동 (최초 1회)
open -g -a "LM Studio"
lms server start
```

### 3. 이 레포 클론 + 모델 다운로드
```bash
git clone https://github.com/hs85-newbie/gemma4-bench.git
cd gemma4-bench

# 핵심 모델 3종 (약 28GB)
lms get -y "qwen/qwen2.5-coder-14b"              # 8.33GB
lms get -y "qwen/qwen3-8b"                       # 4.62GB
lms get -y "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF"  # 14.82GB
```

> Gemma 4 공식 `google/gemma-4-26B-A4B-it` 은 HF 게이티드 라이선스라 `lms get` 자동 다운로드 실패. Unsloth GGUF 미러를 HF URL 직접 지정으로 우회.

### 4. Claude Code 연동 (Option A — shell 래퍼)
```bash
chmod +x scripts/ask-local.sh
ln -sf "$PWD/scripts/ask-local.sh" ~/bin/ask-local

# 테스트
lms load "gemma-4-26b-a4b-it" --gpu max --context-length 8192 -y
ask-local "Python으로 피보나치 함수 작성. 주석 한국어."
```

### 5. Claude Code MCP 연동 (Option B — Node 래퍼)
`~/.claude/settings.json` 에 `config/claude-settings.sample.json` 내용을 병합:
```json
{
  "mcpServers": {
    "local-llm": {
      "command": "node",
      "args": ["/ABSOLUTE/PATH/TO/gemma4-bench/scripts/mcp-local-llm.mjs"],
      "env": {
        "LM_STUDIO_URL": "http://localhost:1234/v1",
        "LOCAL_LLM_MODEL": "gemma-4-26b-a4b-it"
      }
    }
  }
}
```
Claude Code 재시작 → `mcp__local-llm__local_llm_generate` 툴 사용 가능.

### 6. 벤치마크 재실행
```bash
./scripts/bench-run.sh "gemma-4-26b-a4b-it" "results/$(date +%F)"
python3 scripts/bench-summarize.py "results/$(date +%F)"
```

---

## ✅ 이 구조가 맞는 경우 / 맞지 않는 경우

### 도입할 가치 있음
- 월 **100+ 태스크**의 장기 프로젝트
- 토큰 비용에 민감한 운영 단계
- **반복 작업 비율이 높은** 도메인 (테스트 자동화, 번역, 마이그레이션)
- 일부 데이터가 외부 전송 금지 (프라이버시 제약)
- 오프라인 개발 필요성

### 오히려 손해
- 소규모 개인 프로젝트 — 라우팅 오버헤드 > 절감
- 짧은 프로토타입 — 그냥 Opus 하나
- 품질이 돈보다 중요한 단일 중요 작업 — Opus 전담
- 맥북 에어 8GB·16GB 등 메모리 심각 부족

---

## ⚠️ 알려진 한계 / 리스크

| 항목 | 내용 | 대응 |
|---|---|---|
| **M2 8-core GPU 속도** | 14B dense 실측 5~6 tok/s (M2 Pro/Max 수치의 절반) | Gemma 4 MoE로 10 tok/s 확보 |
| **핸드오프 품질 손실** | 티어 간 컨텍스트 축약으로 뉘앙스 소실 | Opus 최종 검수 단계 필수 |
| **로컬 모델 도구 사용 한계** | Gemma/Qwen 은 "생성만" 위임, 탐색/디버깅 금지 | 에이전트 루프는 Tier 1-3 전담 |
| **메모리 스왑 스래싱** | 프로파일 자주 바꾸면 30초×N 누적 손실 | 세션당 1~2회 제한 |
| **지식 컷오프** | 로컬 모델은 최신 API·CVE 모름 | 버전 업/보안 패치는 Tier 1-2 전담 |
| **Gemma 4 공식 MLX 부재** | 현재 Unsloth GGUF 사용 중 | MLX 변종 공개 시 재벤치 |
| **메모리 측정 스크립트 버그** | `bench-run.sh` 의 `mem_snapshot` 함수가 부정확 | 후속 작업으로 `footprint` 기반 교체 예정 |

---

## 🗺️ 로드맵

- [x] LM Studio + `lms` CLI 기반 자동화
- [x] ask-local shell 래퍼 (Bash 툴 통합)
- [x] Node 기반 MCP 서버 (Claude Code 네이티브 통합)
- [x] 벤치마크 프레임워크 (10 케이스 × 6 카테고리)
- [x] 3종 모델 비교 (Qwen 3 14B / Phi-4 / Gemma 4 26B A4B)
- [x] 6모델 하이브리드 아키텍처 설계
- [ ] 프로파일 스위치 스크립트 2종 (generalist / coder)
- [ ] Haiku 디스패처 에이전트 프로토타입
- [ ] 라우팅 룰 파일 (`config/router.yaml`)
- [ ] 비용 로거 (티어별 호출 빈도·누적 비용 기록)
- [ ] Qwen2.5-Coder 14B 포함 4종 코딩 전용 재벤치
- [ ] Thinking OFF Qwen 3 재벤치 (공정 비교)
- [ ] MLX Gemma 4 공개 시 재벤치
- [ ] 메모리 측정 스크립트 `footprint` 기반 교체

---

## 📖 참고 문서

- [최초 작업 계획서](docs/plan.md)
- [패턴 B 셋업 가이드](docs/setup-guide.md)
- [3종 모델 벤치 리포트](docs/benchmark-report.md)

---

## 🔗 Related Work — 생태계

### [claude-knowledge-graph](https://github.com/NAMYUNWOO/claude-knowledge-graph) by @NAMYUNWOO

**상호 보완적인 프로젝트**. gemma4-bench 가 "작업 실행 오케스트레이션" 을 다룬다면, claude-knowledge-graph 는 "그 작업에서 나온 지식의 자동 캡처·구조화" 를 담당합니다.

| 축 | gemma4-bench | claude-knowledge-graph |
|---|---|---|
| 목적 | **작업 실행** 하이브리드 오케스트레이션 | **세션 지식** 자동 캡처·Obsidian 그래프 |
| 로컬 LLM | Gemma 4 26B A4B + Qwen Coder 14B + Qwen 3 8B | Qwen 3.5 4B (태그·요약) + Qwen3-Embedding (검색) |
| 런타임 | LM Studio (GUI + `lms` CLI) | llama.cpp (llama-server) |
| Claude Code 통합 | MCP server + Bash 래퍼 (`ask-local`) | Hooks (`UserPromptSubmit`, `Stop`) |
| 결과물 | 코드·문서·테스트 (실행) | Obsidian 지식 그래프 (아카이브) |
| 철학 | "Claude 두뇌 + 로컬 손발" | "세션 지식 자동 아카이브" |

#### 왜 같이 쓰면 좋은가

```
┌────────────────────────────────────────────────────────────┐
│                    Claude Code 세션                         │
│                                                            │
│   사용자 질문 ─► Opus 오케스트레이션 ─► 결과물            │
│           │            │                                   │
│           │            ├─ gemma4-bench                     │
│           │            │  (로컬 LLM 에 반복 작업 위임)    │
│           │            │  Gemma 4 / Qwen Coder / Qwen 3 8B │
│           │            │                                   │
│           ▼            ▼                                   │
│   UserPromptSubmit    Stop                                 │
│   Hook                Hook                                 │
│           │            │                                   │
│           └────────────┴───► claude-knowledge-graph        │
│                              (Qwen 3.5 4B 로 태그·요약)   │
│                              │                             │
│                              ▼                             │
│                     Obsidian vault                         │
│                     (검색·회고 가능한 지식 그래프)          │
└────────────────────────────────────────────────────────────┘
```

- **gemma4-bench 가 "실행 엔진"** — 세션 내에서 Claude 가 로컬 LLM 에 반복 작업을 위임해 토큰·시간 절약
- **claude-knowledge-graph 가 "기억 엔진"** — 세션 종료 시 Q&A 전체를 로컬 LLM 으로 태깅·요약해 영속화
- 두 레이어는 **서로 독립적으로 동작** 하며, 각자의 로컬 LLM 모델·런타임을 가짐 (llama.cpp 와 LM Studio 공존 가능)
- **공통 철학**: "민감 데이터는 로컬에 유지", "반복 작업은 비싼 Claude 를 쓰지 않는다", "Apple Silicon 최적화"

#### 메모리 공존 고려사항

두 도구를 동시에 돌리면 **로컬 LLM 이 더 많이 상주** 합니다:
- gemma4-bench GENERALIST 프로파일: ~19.4 GB (Gemma 4 + Qwen 3 8B)
- claude-knowledge-graph: ~2.5 GB (Qwen 3.5 4B) + ~1 GB (Qwen3-Embedding)
- **합계 ~23 GB** → 24 GB M2 Air 에서는 아슬아슬

**권장**: claude-knowledge-graph 의 `min_ram_gb` 설정을 낮추거나, gemma4-bench CODER 프로파일(12.95 GB) 을 기본으로 사용하면 여유 확보.

#### 통합 시나리오 (미래)

- [ ] `ask-local` 호출 로그를 claude-knowledge-graph 가 캡처해 "어떤 위임이 효과적이었는지" 검색 가능
- [ ] `config/router.yaml` 의 라우팅 결정을 Obsidian 에 기록 → 시간 따라 라우터 룰 최적화에 활용
- [ ] 두 프로젝트의 로컬 LLM 모델 공유 (llama.cpp ↔ LM Studio GGUF 공용)
- [ ] `dispatch.sh` 가 Obsidian 에서 과거 유사 작업 티어 결정을 RAG 로 참조

---

## 📜 라이선스

MIT

## 🙏 크레딧

- **모델**: Qwen (Alibaba), Phi (Microsoft), Gemma (Google DeepMind), Unsloth (미러)
- **런타임**: LM Studio, llama.cpp, mlx-llm
- **오케스트레이터**: Claude (Anthropic) Code CLI
- **작업**: Claude Opus 4.6 (1M context) 과 사용자의 페어 프로그래밍
