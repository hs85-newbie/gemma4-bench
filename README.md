# gemma4-bench

MacBook Air M2 24GB에서 로컬 LLM 패턴 B(LM Studio + Claude Code 하이브리드) 셋업과 3종 모델 비교 벤치마크를 수행하는 워크스페이스.

## 구조

```
gemma4-bench/
├── scripts/     # 벤치 러너, shell 래퍼, 유틸
├── config/      # LM Studio, MCP, Claude Code 설정 샘플
├── testcases/   # 벤치마크 프롬프트 JSON (10개 케이스)
├── results/     # 모델별 실행 결과 (JSON/MD)
└── docs/        # 셋업 가이드, 벤치 리포트
```

## 세션

- **세션명**: gemma4
- **일자**: 2026-04-13
- **대상 HW**: MacBook Air M2 / 8C GPU / 24GB
- **목표 모델**: Qwen2.5-Coder 14B, Qwen 3 14B, Gemma 4 26B A4B, Phi-4 14B (MLX 4bit)

## 진행 문서

- 전체 계획: `~/docs/reports/2026-04-13-gemma4-로컬LLM셋업계획.md`
- 셋업 가이드: `docs/setup-guide.md` (작성 예정)
- 벤치 리포트: `docs/benchmark-report.md` (작성 예정)
