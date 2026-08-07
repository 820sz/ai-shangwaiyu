# -*- coding: utf-8 -*-
"""实测豆包视觉模型 thinking 参数的真实行为:
对比 6 种参数组合的耗时 + reasoning_content 出现情况。
不打印 API key。
"""
import base64
import json
import os
import sys
import time
import urllib.request

API_KEY = os.environ.get("DOUBAO_API_KEY")
BASE_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
MODEL = "doubao-seed-2-0-lite-260428"  # App 默认识图模型
IMAGE_PATH = os.path.join(os.environ.get("TEMP", "."), "shot_v114.jpg")  # 720x1600 压缩图

SYSTEM_PROMPT = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"所在句子(可选)"}]}'
    "要求：单词给词性，短语/句子给翻译。无标记返回{\"items\":[]}。只输出JSON。简洁思考。"
)

VARIANTS = {
    "1_disabled": {"thinking": {"type": "disabled"}},
    "2_enabled_budget512": {"thinking": {"type": "enabled", "budget_tokens": 512}},
    "3_enabled_budget2048": {"thinking": {"type": "enabled", "budget_tokens": 2048}},
    "4_enabled_nobudget": {"thinking": {"type": "enabled"}},
    "5_auto": {"thinking": {"type": "auto"}},
    "6_no_thinking_param": {},  # 默认行为:官方文档称默认开启深度思考
}


def build_body(extra: dict) -> dict:
    with open(IMAGE_PATH, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    body = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}", "detail": "low"}},
                    {"type": "text", "text": "识别图中被标记的英语内容"},
                ],
            },
        ],
        "max_tokens": 2048,
        "temperature": 0,
        "stream": True,
    }
    body.update(extra)
    return body


def run(name: str, extra: dict) -> dict:
    body = build_body(extra)
    req = urllib.request.Request(
        BASE_URL,
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    t0 = time.time()
    first_byte = None
    first_content = None
    first_reasoning = None
    reasoning_chars = 0
    content_chars = 0
    done = False
    try:
        with urllib.request.urlopen(req, timeout=150) as resp:
            for raw in resp:
                if first_byte is None:
                    first_byte = time.time() - t0
                line = raw.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    done = True
                    break
                try:
                    d = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                choices = d.get("choices") or []
                if not choices:
                    continue
                delta = choices[0].get("delta") or {}
                c = delta.get("content")
                r = delta.get("reasoning_content")
                if c:
                    if first_content is None:
                        first_content = time.time() - t0
                    content_chars += len(c)
                if r:
                    if first_reasoning is None:
                        first_reasoning = time.time() - t0
                    reasoning_chars += len(r)
        elapsed = time.time() - t0
        return {
            "name": name,
            "total_s": round(elapsed, 1),
            "first_byte_s": round(first_byte, 1) if first_byte else None,
            "first_content_s": round(first_content, 1) if first_content else None,
            "first_reasoning_s": round(first_reasoning, 1) if first_reasoning else None,
            "reasoning_chars": reasoning_chars,
            "content_chars": content_chars,
            "done": done,
        }
    except Exception as e:
        return {"name": name, "total_s": round(time.time() - t0, 1), "error": str(e)}


def main():
    results = []
    for name, extra in VARIANTS.items():
        print(f"\n=== {name} ...", flush=True)
        r = run(name, extra)
        results.append(r)
        print(f"    {json.dumps(r, ensure_ascii=False)}", flush=True)
    print("\n\n===== 汇总 =====")
    for r in results:
        print(json.dumps(r, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
