# 패턴 B 셋업 가이드 — LM Studio + Claude Code 하이브리드 멀티 에이전트

**대상 HW**: MacBook Air M2 / 8-core GPU / 24GB unified memory
**목표**: Claude Code(Opus)가 오케스트레이터, 로컬 LM Studio(14B급)가 워커로 동작하여 반복 작업 토큰 비용 절감.

---

## 0. 아키텍처

```
┌─────────────────────────────┐
│   Claude Code (Opus 4.6)    │   ← 계획, 판단, 리뷰
│   main orchestrator         │
└─────────┬───────────────────┘
          │
          ├─► Bash tool: ask-local "프롬프트"          (shell 래퍼)
          ├─► MCP tool:  mcp__local-llm__generate      (Node 래퍼)
          │
          ▼
┌─────────────────────────────┐
│  LM Studio local server     │   localhost:1234 (OpenAI 호환)
│  ─ qwen2.5-coder-14b (MLX)  │   메인 워커
│  ─ qwen3-8b (MLX)            │   빠른 워커 (선택)
└─────────────────────────────┘
```

---

## 1. LM Studio 설치

### 1-1. brew cask 설치
```bash
brew install --cask lm-studio
```

### 1-2. `lms` CLI 심볼릭 링크 (GUI 없이 조작)
```bash
mkdir -p ~/bin
ln -sf "/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms" ~/bin/lms
# PATH 영구 등록 (zsh 기준)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 1-3. 데몬 기동 (최초 1회)
`lms` 는 LM Studio 데몬이 필요하므로 앱을 한 번 띄워 데몬만 활성화:
```bash
open -g -a "LM Studio"    # -g = 포그라운드로 올리지 않음
sleep 5
lms ls                    # 정상 출력되면 성공
```

### 1-4. 로컬 서버 시작
```bash
lms server start
# → Success! Server is now running on port 1234
curl http://localhost:1234/v1/models   # 헬스체크
```

---

## 2. 모델 다운로드

### 2-1. 메인 코더 (필수)
```bash
lms get -y "qwen/qwen2.5-coder-14b"
# MLX 4bit가 자동 선택됨 (~8.3 GB, 10~30분 소요)
```

### 2-2. 빠른 워커 (선택)
```bash
lms get -y "qwen/qwen3-8b"
# ~5 GB, 빠른 서브태스크용
```

### 2-3. 설치 확인
```bash
lms ls
```

> **주의**: `lms get -y <키워드>` 는 스태프 픽 중 첫 결과를 자동 선택합니다. "qwen2.5-coder" 만 넣으면 32B가 선택되어 24GB RAM에서 스왑이 발생하므로 **반드시 14B를 명시**하세요.

---

## 3. 모델 로드 및 서버 확인

```bash
lms load qwen2.5-coder-14b-instruct --gpu max --context-length 8192 -y
lms ps                                  # 로드 상태 확인
curl http://localhost:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-14b-instruct",
    "messages": [{"role":"user","content":"hello"}],
    "max_tokens": 64
  }' | jq .
```

예상 응답 시간: 첫 토큰 1~2초, 15~25 tok/s.

---

## 4. Claude Code 연동

두 가지 방식 중 하나를 선택. **Option A** (shell 래퍼)가 가장 간단.

### Option A. Shell 래퍼 (즉시 사용 가능)

`~/gemma4-bench/scripts/ask-local.sh` 를 `~/bin` 에 링크:
```bash
ln -sf ~/gemma4-bench/scripts/ask-local.sh ~/bin/ask-local
chmod +x ~/bin/ask-local
```

Claude Code 세션 내에서:
```bash
ask-local "TypeScript로 debounce 함수 작성"
echo "복잡한 긴 프롬프트..." | ask-local
ask-local -m qwen3-8b "빠른 답만 필요한 질문"
```

장점: 설정 제로, Bash 툴 한 번이면 호출.
단점: streaming/tool-use 없음.

### Option B. MCP 서버 (Claude Code 정식 통합)

`~/.claude/settings.json` 에 아래 키 병합:
```json
{
  "mcpServers": {
    "local-llm": {
      "command": "node",
      "args": ["/Users/cjons/gemma4-bench/scripts/mcp-local-llm.mjs"],
      "env": {
        "LM_STUDIO_URL": "http://localhost:1234/v1",
        "LOCAL_LLM_MODEL": "qwen2.5-coder-14b-instruct"
      }
    }
  }
}
```

Claude Code 재시작 후 `mcp__local-llm__local_llm_generate` 툴이 노출됩니다.

장점: 네이티브 툴 사용, structured 응답.
단점: 재시작 필요, Node 18+ 필수.

---

## 5. 바이브 코딩 실사용 패턴

### 패턴 1. 반복 보일러플레이트 생성 위임

Claude Code 프롬프트:
> "다음 5개 엔드포인트의 Express 라우터 보일러플레이트는 로컬 워커에 위임하고, 너는 아키텍처 리뷰만 해. POST /users, GET /users/:id, PATCH /users/:id, DELETE /users/:id, GET /users?filter"

Claude 내부 동작:
1. Bash: `ask-local "5개 엔드포인트 라우터 TypeScript..."`
2. 결과 수신 → 파일 저장 → 검토 → 수정

### 패턴 2. 테스트 코드 대량 생성

```bash
ask-local -s "너는 Vitest 단위 테스트 전문가. 입력 함수의 happy path 1개 + edge case 2개 작성." \
          "$(cat src/utils/parseQuery.ts)"
```

### 패턴 3. 주석/문서 한국어화

```bash
cat src/foo.ts | ask-local -s "모든 JSDoc 주석을 한국어로 번역. 코드는 그대로 유지." | tee src/foo.ts.ko
```

---

## 6. 검증 체크리스트

- [ ] `lms server status` → running on 1234
- [ ] `curl localhost:1234/v1/models` → 최소 1개 모델
- [ ] `ask-local "hello"` → 응답 수신
- [ ] Claude Code에서 Bash tool로 `ask-local` 호출 성공
- [ ] (Option B 선택 시) `mcp__local-llm__local_llm_list` 성공

---

## 7. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `lms: command not found` | 심볼릭 링크 누락 | §1-2 재실행 |
| `LM Studio daemon is not running` | 데몬 미기동 | `open -g -a "LM Studio"` 1회 실행 |
| `Error: Failed to connect` | 서버 미시작 | `lms server start` |
| 응답 매우 느림 (< 5 tok/s) | GPU offload 부족 or context 과대 | `--gpu max --context-length 4096` 로 재로드 |
| 메모리 부족 swap 발생 | 14B 이상 모델 or 다른 앱 과다 | 컨텍스트 축소, 불필요 앱 종료, `sudo purge` |
| 응답이 잘림 | `max_tokens` 부족 | `-t 4096` 또는 API 호출 시 상향 |

---

## 8. 후속 작업 제안

1. **자동 로드/언로드 hook**: Claude Code pre/post 툴 훅으로 사용 시에만 로드
2. **모델 프로파일 스위칭**: 작업 종류(코드/요약/번역)에 따라 다른 모델
3. **비용 대시보드**: 로컬/Claude API 호출 비율 로그 → 월 절감액 측정
4. **LoRA 파인튜닝**: 자주 쓰는 패턴(커밋 메시지, JSDoc)을 소형 모델에 주입
