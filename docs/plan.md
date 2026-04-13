# 2026-04-13 gemma4 세션 — 로컬 LLM 셋업 + 벤치마크 계획

**대상 하드웨어**: MacBook Air M2 / 8-core GPU / 24GB unified memory
**목표**: (1) 패턴 B — LM Studio + Claude Code 하이브리드 멀티 에이전트 셋업, (3) 로컬 모델 3종 비교 벤치마크
**작성일**: 2026-04-13
**세션**: gemma4

---

## 0. 전체 요약

| 작업 | 실제 손 작업 | 대기 포함 총 시간 | 병렬 가능 |
|---|---|---|---|
| Task 1. 패턴 B 셋업 가이드 | ~50분 | ~2시간 | 다운로드 중 문서 작성 가능 |
| Task 3. 3종 모델 비교 벤치마크 | ~70분 | ~3~4시간 | Task 1과 병렬 진행 가능 |
| **전체** | **~2시간** | **~4~5시간** | **다운로드 병렬화 시 ~3시간 단축** |

**핵심 병목**: 인터넷 다운로드 속도. 총 다운로드 용량 **~40GB** (MLX 4bit 기준).
100Mbps 회선 기준 ~60분, 500Mbps 기준 ~12분.

---

## Task 1. 패턴 B — LM Studio + Claude Code 셋업 가이드

### 목표
- Claude Code(Opus)가 오케스트레이터, 로컬 LM Studio 서버가 워커로 동작
- 반복 코드 생성/테스트/요약 같은 작업을 로컬 14B에 위임하여 API 토큰 절감
- Claude Code 내부에서 `curl localhost:1234` 또는 MCP로 로컬 모델 호출 가능

### 단계별 상세

#### 1-1. LM Studio 설치 및 초기 설정 (10분)
- **작업 내용**
  - https://lmstudio.ai 에서 macOS 빌드 다운로드
  - `.dmg` 실행 → Applications로 드래그
  - 초기 실행 → 텔레메트리 off, 모델 폴더 기본값 유지 (`~/.cache/lm-studio/models`)
  - 좌측 상단 "Power User" 모드 활성화 (OpenAI 호환 서버 옵션 노출)
- **검증**: GUI 첫 화면 정상 로딩
- **소요**: 10분

#### 1-2. 메인 코더 모델 다운로드 (30~60분, 네트워크 의존)
- **모델**: `Qwen2.5-Coder-14B-Instruct-MLX-4bit` (~8.5GB)
- **다운로드 경로**: LM Studio 내 "Discover" 탭 → 검색 → MLX 4bit 버전 선택
- **대체 경로**: `mlx-community/Qwen2.5-Coder-14B-Instruct-4bit` (HuggingFace)
- **검증**: 모델 카드 로드 성공, 예상 메모리 ~9GB 표시
- **소요**: 다운로드 30~60분 (회선 의존) / 손 작업 2분

#### 1-3. 보조 워커 모델 다운로드 (20~40분)
- **모델**: `Qwen3-8B-Instruct-MLX-4bit` (~5GB)
- **용도**: 빠른 탐색, 요약, 툴 호출 워커
- **다운로드**: LM Studio Discover에서 병렬 다운로드 가능
- **검증**: 모델 카드 정상 로드
- **소요**: 20~40분 (병렬) / 손 작업 2분

#### 1-4. LM Studio OpenAI 호환 서버 실행 및 검증 (10분)
- **작업 내용**
  - "Local Server" 탭 진입
  - Qwen2.5-Coder-14B 로드 (Load Model 버튼)
  - Context Length: 32768 설정
  - GPU Offload: 최대 (M2 Metal 활용)
  - Start Server (포트 1234 기본)
- **검증**: 아래 curl 명령으로 응답 확인
  ```bash
  curl http://localhost:1234/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"qwen2.5-coder-14b","messages":[{"role":"user","content":"hello"}]}'
  ```
- **예상 지표**: 첫 토큰 1~2초, 15~25 tok/s
- **소요**: 10분

#### 1-5. Claude Code 연동 설정 (20~30분)
두 가지 연동 방식 중 선택:

**Option A. MCP 서버 방식 (권장)**
- `@modelcontextprotocol/server-openai` 또는 자작 MCP 래퍼 설치
- `~/.claude/settings.json`에 MCP 서버 등록:
  ```json
  {
    "mcpServers": {
      "local-llm": {
        "command": "node",
        "args": ["/path/to/local-llm-mcp-server.js"],
        "env": { "LM_STUDIO_URL": "http://localhost:1234/v1" }
      }
    }
  }
  ```
- Claude Code 재시작 → `mcp__local-llm__*` 툴 노출 확인

**Option B. Shell 래퍼 스크립트 방식 (간단)**
- `~/bin/ask-local`에 bash 스크립트 작성:
  ```bash
  #!/usr/bin/env bash
  curl -s http://localhost:1234/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg prompt "$*" '{model:"qwen2.5-coder-14b",messages:[{role:"user",content:$prompt}]}')" \
    | jq -r '.choices[0].message.content'
  ```
- Claude Code에서 Bash 툴로 `ask-local "반복 작업 프롬프트"` 호출
- **장점**: MCP 없이 즉시 사용 가능 / **단점**: tool use, streaming 미지원

- **검증**: Claude Code 세션에서 로컬 모델로 위임 태스크 1회 성공
- **소요**: Option A 30분 / Option B 15분

#### 1-6. 실제 바이브 코딩 시나리오 검증 (30분)
- **테스트 시나리오 3종**
  1. 보일러플레이트 생성: "TypeScript Express 라우터 CRUD 5개" → 로컬 위임
  2. 테스트 코드 생성: 기존 함수 파일 주고 Vitest 단위 테스트 작성 → 로컬 위임
  3. 주석 번역/작성: 영어 주석 → 한국어 JSDoc 변환 → 로컬 위임
- **측정 지표**
  - 실제 응답 품질 (Claude가 수정 필요한 비율)
  - 토큰 절감률 (Claude API 전용 대비)
  - 레이턴시 (end-to-end)
- **소요**: 30분

#### 1-7. 가이드 문서화 (20분)
- `~/docs/reports/2026-04-13-gemma4-패턴B-셋업가이드.md` 별도 작성
- 스크린샷 포함, 재현 가능한 명령어 블록

### Task 1 시간 합계
| 항목 | 손 작업 | 대기 |
|---|---|---|
| 1-1 설치 | 10분 | - |
| 1-2 + 1-3 다운로드 | 4분 | 40~80분 (병렬) |
| 1-4 서버 검증 | 10분 | - |
| 1-5 연동 설정 | 20~30분 | - |
| 1-6 시나리오 검증 | 30분 | - |
| 1-7 문서화 | 20분 | - |
| **합계** | **~100분** | **+ 다운로드 40~80분** |

---

## Task 3. 로컬 모델 3종 다운로드·비교 벤치마크

### 목표
- 동일한 하드웨어/프롬프트로 **Qwen3, Gemma 4, Phi-4** 비교
- 코드 생성 / 추론 / 한국어 / 툴 사용 4개 축 평가
- "이 스펙에서 바이브 코딩용 로컬 모델 1등"을 객관 데이터로 확정

### 비교 대상 선정 (확정)

| # | 모델 | 양자화 | 메모리 | 역할 |
|---|---|---|---|---|
| A | **Qwen 3 14B** | MLX 4bit | ~10GB | 범용·툴 사용 대표 |
| B | **Gemma 4 26B A4B** (MoE) | MLX 4bit | ~18GB | 스윗스팟 후보 |
| C | **Phi-4 14B** | MLX 4bit | ~9GB | 추론·수학 특화 |

> Task 1에서 다운로드한 Qwen2.5-Coder 14B는 **코드 전용 레퍼런스**로 추가 비교 가능.

### 단계별 상세

#### 3-1. 모델 다운로드 (병렬 60~90분)
- **Qwen 3 14B MLX 4bit**: ~10GB
- **Gemma 4 26B A4B MLX 4bit**: ~18GB ← 최대
- **Phi-4 14B MLX 4bit**: ~9GB
- **총 다운로드**: ~37GB
- **병렬 처리**: LM Studio는 동시 다운로드 3개까지 허용 → 회선 대역폭 공유
- **검증**: 각 모델 카드 정상 로드
- **소요**: 네트워크 의존 60~90분 / 손 작업 5분

#### 3-2. 벤치마크 프레임워크 준비 (30분)
- **스크립트**: `~/bench/local-llm-compare.sh`
- **기능**
  - 모델 이름을 인자로 받아 LM Studio 서버에 로드/언로드
  - 테스트 케이스 JSON을 순차 실행
  - 응답 + 레이턴시 + tokens/sec 기록
  - 결과를 `results/YYYY-MM-DD-model.json`에 저장
- **테스트 케이스 JSON 구조** (10개 케이스)
  ```json
  [
    {"id":"code-01","category":"code","prompt":"TypeScript로 LRU 캐시 구현..."},
    {"id":"code-02","category":"code","prompt":"React hook 커스텀 useDebounce..."},
    {"id":"reason-01","category":"reasoning","prompt":"다음 SQL 쿼리의 문제점..."},
    {"id":"reason-02","category":"reasoning","prompt":"알고리즘 복잡도 분석..."},
    {"id":"ko-01","category":"korean","prompt":"기술 문서 요약..."},
    {"id":"ko-02","category":"korean","prompt":"에러 메시지를 한국어 친화 문구로..."},
    {"id":"tool-01","category":"tool","prompt":"함수 호출 JSON 생성..."},
    {"id":"tool-02","category":"tool","prompt":"MCP 툴 스키마 따라 응답..."},
    {"id":"long-01","category":"long","prompt":"16K 토큰 코드베이스 요약..."},
    {"id":"agent-01","category":"agent","prompt":"다단계 계획 수립..."}
  ]
  ```
- **소요**: 30분

#### 3-3. 모델 로드 및 벤치 실행 (60~90분)
- **순차 실행 필수** (24GB 메모리 제약)
- 각 모델당 평균:
  - 로드: 30초~1분
  - 10개 케이스 실행: 15~25분
  - 언로드: 10초
- **3개 모델 × 20분 = 60분**
- **측정 항목**
  - tokens/sec (생성 속도)
  - time-to-first-token
  - 피크 메모리 사용량 (`footprint` 명령 또는 Activity Monitor 스크립트)
  - 응답 완전성 (truncation 여부)
- **소요**: 60~90분

#### 3-4. 품질 평가 (30분)
- **자동 점수**: 속도·메모리는 스크립트가 기록
- **수동 점수**: 10개 케이스 × 3모델 = 30개 응답 → 5점 척도로 직접 평가
  - 정확성, 완전성, 한국어 자연스러움, 툴 포맷 준수
- **교차 검증 옵션**: Claude Opus에 "3개 응답 중 어느 것이 가장 좋은가" 물어 비교 (추가 토큰 소모)
- **소요**: 30분

#### 3-5. 결과 리포트 작성 (30분)
- **산출물**: `~/docs/reports/2026-04-13-gemma4-3종모델벤치.md`
- **포함**
  - 모델별 스코어 표
  - 레이턴시/속도 그래프 (텍스트 기반)
  - 카테고리별 승자
  - 최종 추천: "바이브 코딩 메인 = X, 서브 워커 = Y"
- **소요**: 30분

### Task 3 시간 합계
| 항목 | 손 작업 | 대기 |
|---|---|---|
| 3-1 다운로드 | 5분 | 60~90분 |
| 3-2 프레임워크 | 30분 | - |
| 3-3 벤치 실행 | 10분 (모니터링) | 60~90분 |
| 3-4 품질 평가 | 30분 | - |
| 3-5 리포트 | 30분 | - |
| **합계** | **~105분** | **+ 다운로드·실행 120~180분** |

---

## 병렬 진행 타임라인 (권장)

```
시각    | Task 1                     | Task 3
--------|----------------------------|---------------------------
0:00    | 1-1 LM Studio 설치         |
0:10    | 1-2,3 모델 다운로드 시작  | 3-1 다운로드 시작 (병렬)
0:15    |                            | 3-2 프레임워크 스크립트 작성
0:45    |                            | 스크립트 완성, 다운로드 대기
1:00    | 다운로드 완료              | 일부 다운로드 완료
1:05    | 1-4 서버 검증              |
1:15    | 1-5 Claude Code 연동       |
1:45    | 1-6 시나리오 검증          |
2:15    | 1-7 가이드 문서화          |
2:35    | Task 1 완료                | 모든 다운로드 완료
2:40    |                            | 3-3 벤치 실행 (Qwen3 → Gemma4 → Phi-4)
3:40    |                            | 3-4 품질 평가
4:10    |                            | 3-5 리포트 작성
4:40    |                            | Task 3 완료
```

**총 소요**: 약 4시간 40분 (순차 진행 시 ~6시간 → 1시간 20분 단축)

---

## 리스크 및 대응

| 리스크 | 확률 | 영향 | 대응 |
|---|---|---|---|
| Gemma 4 26B A4B 메모리 부족 | 중 | 벤치 불가 | E4B로 대체, 혹은 컨텍스트 4K로 축소 |
| MLX 버전 호환성 문제 | 저 | 속도 저하 | GGUF(llama.cpp) 폴백 |
| LM Studio MCP 미지원 | 중 | 연동 실패 | shell 래퍼(Option B) 폴백 |
| 다운로드 속도 느림 | 중 | 타임라인 연장 | 저녁/야간 백그라운드 다운로드 |
| 벤치 스크립트 버그 | 중 | 재실행 필요 | 각 모델 로드 직후 1개 케이스 smoke test |
| 24GB 메모리 스왑으로 속도 저하 | 중 | 결과 왜곡 | `sudo purge` 후 재실행, 불필요 앱 종료 |

---

## 성공 기준 (완료 정의)

### Task 1
- [ ] Claude Code 세션 내에서 로컬 14B 모델로 태스크 1건 성공 위임
- [ ] 보일러플레이트 생성 속도 15 tok/s 이상
- [ ] 셋업 가이드 md 파일 작성 완료

### Task 3
- [ ] 3개 모델 × 10개 케이스 = 30건 응답 수집
- [ ] 모델별 tok/s, 메모리, 품질 점수 표 완성
- [ ] "바이브 코딩 메인/서브 워커" 최종 추천 md 작성

---

## 후속 작업 (이 계획 완료 후)

1. **패턴 B 자동화**: 로컬 모델 자동 로드/언로드 스크립트 (메모리 관리)
2. **멀티 워커 실험**: Qwen 3 8B 2개 병렬 로드 후 CrewAI로 역할 분리 (Task 3 결과 반영)
3. **토큰 비용 대시보드**: 로컬/클라우드 위임 비율 기록 → 월 절감액 측정
4. **파인튜닝 시도**: 자주 쓰는 패턴(커밋 메시지, JSDoc)을 LoRA로 소형 모델에 주입
