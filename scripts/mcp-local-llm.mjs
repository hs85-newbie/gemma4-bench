#!/usr/bin/env node
// mcp-local-llm — Claude Code에서 로컬 LM Studio를 호출하는 MCP 서버
//
// 제공 툴:
//   local_llm_generate  — 단일 프롬프트 → 응답
//   local_llm_list      — 로드된 모델 조회
//
// 환경변수:
//   LM_STUDIO_URL    (기본 http://localhost:1234/v1)
//   LOCAL_LLM_MODEL  (기본 qwen2.5-coder-14b-instruct)
//
// 의존성: Node 18+ 내장 fetch, MCP 프로토콜은 JSON-RPC 2.0 over stdio

import { createInterface } from "node:readline";
import { stdin, stdout, stderr } from "node:process";

const URL = process.env.LM_STUDIO_URL || "http://localhost:1234/v1";
const DEFAULT_MODEL = process.env.LOCAL_LLM_MODEL || "qwen2.5-coder-14b-instruct";
const SERVER_NAME = "local-llm";
const SERVER_VERSION = "0.1.0";

// MCP 툴 정의
const TOOLS = [
  {
    name: "local_llm_generate",
    description:
      "로컬 LM Studio에 프롬프트를 보내 응답을 받는다. 반복 코드 생성, 테스트 케이스 작성, 주석 변환 등 토큰 비용이 아까운 작업에 사용.",
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "사용자 프롬프트" },
        system: { type: "string", description: "(선택) 시스템 프롬프트" },
        model: {
          type: "string",
          description: `(선택) 모델 ID. 기본 ${DEFAULT_MODEL}`,
        },
        temperature: { type: "number", description: "(선택) 기본 0.2" },
        max_tokens: { type: "number", description: "(선택) 기본 2048" },
      },
      required: ["prompt"],
    },
  },
  {
    name: "local_llm_list",
    description: "LM Studio 서버에 현재 로드된 모델 목록을 반환.",
    inputSchema: { type: "object", properties: {} },
  },
];

// JSON-RPC 응답 유틸
function send(msg) {
  stdout.write(JSON.stringify(msg) + "\n");
}
function ok(id, result) {
  send({ jsonrpc: "2.0", id, result });
}
function err(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

// LM Studio 호출
async function callLocalLLM({
  prompt,
  system,
  model = DEFAULT_MODEL,
  temperature = 0.2,
  max_tokens = 2048,
}) {
  const messages = [];
  if (system) messages.push({ role: "system", content: system });
  messages.push({ role: "user", content: prompt });

  const res = await fetch(`${URL}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model, messages, temperature, max_tokens, stream: false }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`LM Studio ${res.status}: ${text}`);
  }

  const data = await res.json();
  return {
    content: data.choices?.[0]?.message?.content ?? "",
    usage: data.usage ?? null,
  };
}

async function listModels() {
  const res = await fetch(`${URL}/models`);
  if (!res.ok) throw new Error(`LM Studio ${res.status}`);
  const data = await res.json();
  return data.data?.map((m) => m.id) ?? [];
}

// MCP 요청 처리
async function handle(req) {
  const { id, method, params } = req;
  try {
    switch (method) {
      case "initialize":
        return ok(id, {
          protocolVersion: "2025-06-18",
          capabilities: { tools: {} },
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
        });

      case "tools/list":
        return ok(id, { tools: TOOLS });

      case "tools/call": {
        const { name, arguments: args = {} } = params || {};
        if (name === "local_llm_generate") {
          const { content, usage } = await callLocalLLM(args);
          return ok(id, {
            content: [{ type: "text", text: content }],
            _meta: { usage },
          });
        }
        if (name === "local_llm_list") {
          const models = await listModels();
          return ok(id, {
            content: [{ type: "text", text: JSON.stringify(models, null, 2) }],
          });
        }
        return err(id, -32601, `Unknown tool: ${name}`);
      }

      case "notifications/initialized":
        return; // 알림은 응답 없음

      default:
        return err(id, -32601, `Method not found: ${method}`);
    }
  } catch (e) {
    stderr.write(`[mcp-local-llm] ${e.message}\n`);
    return err(id, -32603, e.message);
  }
}

// stdio 루프
const rl = createInterface({ input: stdin });
rl.on("line", async (line) => {
  line = line.trim();
  if (!line) return;
  try {
    const req = JSON.parse(line);
    await handle(req);
  } catch (e) {
    stderr.write(`[mcp-local-llm] parse error: ${e.message}\n`);
  }
});
