# claude-knowledge-graph 통합 가이드

> **목표**: [NAMYUNWOO/claude-knowledge-graph](https://github.com/NAMYUNWOO/claude-knowledge-graph)(KG 도구)를 **자체 llama-server 없이** gemma4-bench 의 기존 LM Studio 인프라(Gemma 4 + Qwen 3 8B) 만 재사용해 구동한다.
>
> **핵심 절감**: 추가 llama-server 프로세스 0개, 추가 모델 다운로드 0~0.6GB, 추가 메모리 상주 0~0.6GB.
>
> **상태**: 설계 완료, 실제 설치·패치는 Phase 1 검증 이후.

---

## 0. TL;DR

| | 원래 KG 도구 | 통합 후 |
|---|---|---|
| 런타임 | llama.cpp + llama-server (자체 spawn) | **LM Studio 재사용** |
| 채팅 모델 | Qwen 3.5 4B (~2.5 GB) | **Gemma 4 26B A4B (14.82 GB)** — 이미 상주 |
| 임베딩 모델 | Qwen3-Embedding (~1 GB) 별도 llama-server | Nomic v1.5 (0.08 GB) — 이미 설치 |
| 추가 메모리 | +4.5 GB | **0 GB** (완전 재사용) or +0.6 GB (임베딩 품질 보강 시) |
| 런타임 프로세스 수 | LM Studio + llama-server × 2 (채팅/임베딩) | **LM Studio 하나만** |
| 설정 복잡도 | 2 서버 포트·모델 경로 관리 | **환경변수 3개** |
| 태깅 품질 | Qwen 3.5 4B 수준 | **Gemma 4 26B 수준 (상승 기대)** |

**필요 작업**: KG 도구 Python 패키지에 **3가지 작은 패치**. 총 코드 15~20 줄.

---

## 1. 왜 이 통합이 의미있는가

### gemma4-bench 입장
- 이미 Gemma 4 + Qwen 3 8B 가 상시 로드됨 (autostart 로 자동)
- 로컬 LLM 재사용 원칙("두뇌 vs 손발" 철학과 정합)
- 메모리 사용 최적화

### KG 도구 입장
- llama.cpp 설치·빌드·모델 다운로드 오버헤드 제거
- 더 강력한 모델(Gemma 4 26B A4B MoE)로 태깅·요약 품질 상승 가능성
- LM Studio 의 GUI 관리 혜택(모델 스위치·로그 열람)

### 공통
- Apple Silicon 한 대에서 두 시스템이 리소스 경쟁 없이 공존
- 인프라 단일화 → 디버깅·운영 단순화

---

## 2. 사전 조건

- [x] gemma4-bench Phase 1-1 완료 (autostart 로 GENERALIST 프로파일 상주)
- [x] LM Studio 서버 포트 1234 응답 (`curl localhost:1234/v1/models` 확인)
- [x] `gemma-4-26b-a4b-it` 모델 로드됨
- [x] `text-embedding-nomic-embed-text-v1.5` 임베딩 모델 설치됨 (LM Studio 초기 번들)
- [ ] Python 3.10+ (KG 도구 의존성)
- [ ] Obsidian 앱 (선택, GUI 지식 그래프 탐색용)
- [ ] (권장) Phase 1 **실사용 30일 관찰 이후** 도입 — 둘을 동시에 세팅하면 문제 원인 분리 어려움

---

## 3. 아키텍처 변경

### 원래 KG 도구 흐름

```
Claude Code Session
    │ Stop hook
    ▼
qwen_processor.py
    │ start_server()           ← 매번 llama-server spawn
    ▼
subprocess.Popen([
  "llama-server",
  "--model", "Qwen3.5-4B-Q4_K_M.gguf",
  "--port", "8199",
  ...
])
    │
    ▼
OpenAI(base_url="http://127.0.0.1:8199/v1")
    │ chat.completions.create(model="qwen")
    ▼
llama-server (Qwen 3.5 4B 로드됨)
    │
    ▼
JSON 응답
```

### 통합 후 흐름

```
Claude Code Session
    │ Stop hook
    ▼
qwen_processor.py  (3줄 패치된 버전)
    │ start_server()           ← 헬스체크 후 skip
    ▼
OpenAI(base_url="http://127.0.0.1:1234/v1")   ← LM Studio
    │ chat.completions.create(
    │   model="gemma-4-26b-a4b-it",             ← 패치된 환경변수에서 읽음
    │   ...
    │ )
    ▼
LM Studio (이미 Gemma 4 상주 중)
    │
    ▼
JSON 응답
```

---

## 4. 필요한 패치 3종

KG 도구는 `pip install -e .` 로 설치하므로 로컬 파일을 직접 수정하면 됨 (`~/path/to/claude-knowledge-graph/src/claude_knowledge_graph/qwen_processor.py`).

### 패치 1️⃣ — `call_qwen()` 모델 이름 환경변수화

**파일**: `src/claude_knowledge_graph/qwen_processor.py`
**위치**: `call_qwen()` 함수 내부 `chat.completions.create(...)` 호출

**Before**:
```python
def call_qwen(prompt: str) -> dict | None:
    """Call Qwen via llama-server's OpenAI-compatible API."""
    from openai import OpenAI

    client = OpenAI(
        base_url=f"http://127.0.0.1:{LLAMA_PORT}/v1",
        api_key="not-needed",
    )

    messages = [...]

    try:
        response = client.chat.completions.create(
            model="qwen",
            messages=messages,
            max_tokens=LLAMA_MAX_TOKENS,
            ...
        )
```

**After**:
```python
def call_qwen(prompt: str) -> dict | None:
    """Call Qwen (or compatible) via OpenAI-compatible API (llama-server or LM Studio)."""
    import os
    from openai import OpenAI

    # Support reuse of external OpenAI-compatible server (e.g. LM Studio)
    base_url = os.environ.get(
        "CKG_BASE_URL",
        f"http://127.0.0.1:{LLAMA_PORT}/v1",
    )
    model_name = os.environ.get("CKG_MODEL_NAME", "qwen")

    client = OpenAI(
        base_url=base_url,
        api_key=os.environ.get("CKG_API_KEY", "not-needed"),
    )

    messages = [...]

    try:
        response = client.chat.completions.create(
            model=model_name,
            messages=messages,
            max_tokens=LLAMA_MAX_TOKENS,
            ...
        )
```

**효과**:
- `CKG_BASE_URL=http://127.0.0.1:1234/v1` 설정 시 LM Studio 호출
- `CKG_MODEL_NAME=gemma-4-26b-a4b-it` 설정 시 Gemma 4 로 추론
- 미설정 시 기존 동작 유지 (하위 호환)

---

### 패치 2️⃣ — `start_server()` 외부 서버 감지 시 스킵

**파일**: `src/claude_knowledge_graph/qwen_processor.py`
**위치**: `start_server()` 함수 맨 앞

**Before**:
```python
def start_server() -> subprocess.Popen:
    """Start llama-server and wait until it's ready."""
    global _server_proc
    if _server_proc is not None and _server_proc.poll() is None:
        return _server_proc

    server_bin = Path(LLAMA_SERVER_BIN)
    ...
```

**After**:
```python
def start_server() -> subprocess.Popen | None:
    """Start llama-server, or reuse an external OpenAI-compatible server if CKG_BASE_URL is set."""
    import os
    global _server_proc

    # Reuse external server (LM Studio 등) — spawn 스킵
    if os.environ.get("CKG_BASE_URL"):
        import urllib.request
        try:
            url = os.environ["CKG_BASE_URL"].rstrip("/") + "/models"
            urllib.request.urlopen(url, timeout=3)
            log(f"Reusing external OpenAI-compatible server: {os.environ['CKG_BASE_URL']}")
            return None  # 외부 서버 사용, subprocess 필요 없음
        except Exception as e:
            log(f"External server at CKG_BASE_URL unreachable: {e}, falling back to local spawn")

    if _server_proc is not None and _server_proc.poll() is None:
        return _server_proc

    server_bin = Path(LLAMA_SERVER_BIN)
    ...
```

**효과**:
- `CKG_BASE_URL` 설정 시: 헬스체크 성공하면 spawn 안 함, 기존 서버 재사용
- 헬스체크 실패 시: 경고 로그 후 기존 spawn 동작으로 폴백 (안전)
- `CKG_BASE_URL` 미설정 시: 기존 동작 100% 유지

---

### 패치 3️⃣ — `stop_server()` 외부 서버일 때 no-op

**파일**: `src/claude_knowledge_graph/qwen_processor.py`
**위치**: `stop_server()` 함수 (있을 경우)

**Before**:
```python
def stop_server() -> None:
    global _server_proc
    if _server_proc and _server_proc.poll() is None:
        _server_proc.terminate()
        _server_proc.wait(timeout=5)
        _server_proc = None
```

**After**:
```python
def stop_server() -> None:
    """Stop spawned llama-server. No-op when reusing external server."""
    import os
    global _server_proc

    # 외부 서버를 쓰는 경우 종료할 것 없음
    if os.environ.get("CKG_BASE_URL"):
        return

    if _server_proc and _server_proc.poll() is None:
        _server_proc.terminate()
        _server_proc.wait(timeout=5)
        _server_proc = None
```

**효과**: LM Studio 를 우리가 관리하는 상태에서, KG 도구가 실수로 종료 시도 안 하게.

---

### 임베딩 처리 (패치 대상 여부는 검증 필요)

`src/claude_knowledge_graph/embeddings.py` 도 유사 패턴으로 패치 가능. 구체 코드는 실제 파일 확인 후 작성. 기본 전략:
- `CKG_EMBEDDING_BASE_URL` 환경변수 추가
- `CKG_EMBEDDING_MODEL` 로 LM Studio 의 `text-embedding-nomic-embed-text-v1.5` 지정
- 별도 llama-server(임베딩용) spawn 스킵

Nomic v1.5 로 시작 → 한국어 검색 품질 부족 시 `Qwen3-Embedding-0.6B` GGUF 를 LM Studio 에 추가 설치 (~600MB).

---

## 5. 설치 순서 (Phase 1 검증 후 실행)

### Step 1. KG 도구 설치
```bash
cd ~/src  # 또는 선호 경로
git clone https://github.com/NAMYUNWOO/claude-knowledge-graph.git
cd claude-knowledge-graph
pip install -e .
```

### Step 2. 패치 적용
```bash
# 패치 1, 2, 3 을 src/claude_knowledge_graph/qwen_processor.py 에 직접 반영
vim src/claude_knowledge_graph/qwen_processor.py

# 또는 patch 파일 미리 준비해서 적용
patch -p1 < ~/gemma4-bench/patches/ckg-lmstudio-reuse.patch
```

### Step 3. 환경변수 설정

`~/.anthropic/env` 에 추가 (gemma4-bench Phase 1-3 에서 만든 파일 재활용):
```bash
# claude-knowledge-graph ↔ LM Studio 재사용
export CKG_BASE_URL="http://127.0.0.1:1234/v1"
export CKG_MODEL_NAME="gemma-4-26b-a4b-it"
export CKG_EMBEDDING_BASE_URL="http://127.0.0.1:1234/v1"
export CKG_EMBEDDING_MODEL="text-embedding-nomic-embed-text-v1.5"

# Obsidian vault 경로
export CKG_VAULT_DIR="$HOME/Documents/Obsidian/MyVault"
```

### Step 4. Obsidian vault 생성
```bash
mkdir -p ~/Documents/Obsidian/MyVault
# Obsidian 앱에서 해당 경로를 vault 로 등록
```

### Step 5. Claude Code Hooks 등록
KG 도구 README 참조 — `~/.claude/settings.json` 의 `hooks` 섹션에 추가:
```json
{
  "hooks": {
    "UserPromptSubmit": [{"command": "ckg capture-prompt"}],
    "Stop": [{"command": "ckg capture-stop"}]
  }
}
```

### Step 6. 첫 세션 테스트
```bash
# 터미널 A: Claude Code 에서 간단한 질문 하나
# (Stop 훅이 KG 도구를 백그라운드 실행)

# 터미널 B: 로그 관찰
tail -f ~/.local/share/claude-knowledge-graph/logs/qwen_processor.log
```

성공 지표:
- 로그에 `Reusing external OpenAI-compatible server: http://127.0.0.1:1234/v1` 출력
- `~/Documents/Obsidian/MyVault/knowledge-graph/daily/YYYY-MM-DD.md` 생성 확인
- llama-server 프로세스가 **spawn 안 됨** (`pgrep llama-server` 무응답)

---

## 6. 환경변수 레퍼런스

| 변수 | 역할 | 권장값 | 필수 |
|---|---|---|---|
| `CKG_BASE_URL` | 채팅 OpenAI 호환 API URL | `http://127.0.0.1:1234/v1` | ✓ |
| `CKG_MODEL_NAME` | 채팅 모델 ID | `gemma-4-26b-a4b-it` | ✓ |
| `CKG_API_KEY` | API 키 (LM Studio 는 무시) | `not-needed` | ✗ |
| `CKG_EMBEDDING_BASE_URL` | 임베딩 API URL | `http://127.0.0.1:1234/v1` | ✓ |
| `CKG_EMBEDDING_MODEL` | 임베딩 모델 ID | `text-embedding-nomic-embed-text-v1.5` | ✓ |
| `CKG_VAULT_DIR` | Obsidian vault 루트 | `$HOME/Documents/Obsidian/MyVault` | ✓ |
| `CKG_LLAMA_SERVER` | (폴백용) llama-server 경로 | `/opt/homebrew/bin/llama-server` | ✗ |
| `CKG_MODEL_PATH` | (폴백용) GGUF 경로 | 미설정 | ✗ |

---

## 7. 검증 체크리스트

- [ ] `curl http://localhost:1234/v1/models` 가 `gemma-4-26b-a4b-it` 포함
- [ ] `CKG_BASE_URL` 설정 후 `ckg test` 수동 실행 → "Reusing external server" 로그
- [ ] `pgrep llama-server` 결과 없음 (KG 도구가 spawn 하지 않음)
- [ ] Claude Code 세션 후 `daily/YYYY-MM-DD.md` 생성 확인
- [ ] Obsidian 에서 concept 노트 링크 그래프 시각화 정상
- [ ] 태깅 품질 스팟 체크 5개: Qwen 3.5 4B 대비 개선 or 동등
- [ ] `lms ps` 로 Gemma 4 + Qwen 3 8B 여전히 로드 중 (메모리 변동 없음)

---

## 8. 롤백 방법

통합이 실패하거나 불안정하면:

1. `~/.anthropic/env` 에서 `CKG_BASE_URL` 등 환경변수 주석 처리
2. 새 셸 세션 → KG 도구가 기본 llama-server spawn 모드로 복귀
3. 필요 시 `llama.cpp` + Qwen 3.5 4B GGUF 기본 설치로 원래 설계 따름
4. Claude Code Hooks 설정은 그대로 유지 (양쪽 모두 동일 명령어)

환경변수만 바꿔서 전환 가능 — **코드 롤백 불필요** (패치가 하위 호환이므로).

---

## 9. 업스트림 기여 제안

이 통합 패턴은 KG 도구 사용자 전원에게 유용할 가능성 있음. [NAMYUNWOO/claude-knowledge-graph](https://github.com/NAMYUNWOO/claude-knowledge-graph) 에 PR 제안:

**제안 제목**: *"Allow reuse of external OpenAI-compatible server (LM Studio, Ollama, vLLM 등)"*

**제안 요지**:
1. `CKG_BASE_URL` / `CKG_MODEL_NAME` 환경변수 추가
2. `start_server()` 가 외부 서버 감지 시 spawn 스킵
3. 기존 `llama-server` 자동 관리 동작은 기본값 유지 (하위 호환)
4. README 에 "Advanced: Reuse existing LM Studio / Ollama" 섹션 추가

**가치**:
- llama.cpp 빌드 경험 없는 사용자 진입 장벽 낮춤
- 여러 로컬 LLM 도구와 공존 가능
- 다중 프로젝트 간 모델·메모리 공유

---

## 10. 알려진 리스크

| 리스크 | 대응 |
|---|---|
| Gemma 4 의 응답이 KG 도구의 JSON 스키마 준수 실패율이 Qwen 3.5 4B 보다 낮을 가능성 | 첫 주 로그 모니터링, 실패율 >10% 시 `CKG_MODEL_NAME=qwen/qwen3-8b` 로 교체 |
| LM Studio 재시작·모델 언로드 시 KG 도구 호출 실패 | 패치 2 의 헬스체크 폴백으로 경고 로그만 남기고 계속 |
| 한국어 임베딩 품질 저하 | Nomic → Qwen3-Embedding-0.6B 교체 (+0.6GB) |
| Gemma 4 의 처리 속도가 4B 모델보다 느려서 백그라운드 누적 | 큐 크기 모니터링, 병목 시 Qwen 3 8B 로 교체 (4.62GB, 이미 상주) |
| KG 도구 업스트림 변경과 패치 충돌 | 환경변수 기반 패치라 충돌 영역 좁음, 업스트림 PR 머지 시 자동 해소 |

---

## 11. 실행 판단 (의사결정 플로우)

```
Phase 1 검증 30일 완료?
├─ No  → 이 통합 실행 금지 (원인 분리 어려움)
└─ Yes
    │
    ├─ gemma4-bench 실사용 안착했는가?
    ├─ No  → 이 통합 보류, gemma4-bench 개선 우선
    └─ Yes
        │
        ├─ 세션 지식 누락이 실제 문제인가?
        │  (~/docs/reports/ 수동 작성 만으로 부족한가?)
        ├─ No  → 통합 필요 없음, YAGNI
        └─ Yes
            │
            ├─ 이 문서 기반 통합 실행
            ├─ 패치 3종 적용
            ├─ 환경변수 설정
            └─ 1주일 관찰 후 품질 판단
                ├─ Good → 업스트림 PR
                └─ Bad  → 롤백 + 원인 분석
```

---

## 부록: KG 도구 소스 분석 결과

검증된 사실 (2026-04-14 기준, NAMYUNWOO/claude-knowledge-graph main 브랜치):

| 파일 | 발견 |
|---|---|
| `pyproject.toml` | `dependencies = ["openai>=1.0", "click>=8.0"]` — OpenAI SDK 사용 |
| `src/claude_knowledge_graph/config.py` | `LLAMA_PORT=8199` (env `CKG_LLAMA_PORT` 로 override 가능), `LLAMA_SERVER_BIN`, `GGUF_MODEL_PATH` 환경변수 지원 |
| `src/claude_knowledge_graph/qwen_processor.py` L312-316 | `client = OpenAI(base_url=f"http://127.0.0.1:{LLAMA_PORT}/v1", api_key="not-needed")` |
| `src/claude_knowledge_graph/qwen_processor.py` L329 | `response = client.chat.completions.create(model="qwen", ...)` — **`model="qwen"` 하드코딩** |
| `src/claude_knowledge_graph/qwen_processor.py` `start_server()` | 매 호출마다 subprocess 로 llama-server spawn |

**결론**: 패치 대상이 명확하고 작음. 드롭인 통합 가능.
