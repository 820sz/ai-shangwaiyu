# -*- coding: utf-8 -*-
"""第四轮:书本照片 + 旧 prompt + 思考模式(low/high)——省略号是否由 prompt 引起。
App 当前使用的就是旧 prompt。不打印 API key。
"""
import base64
import json
import os
import sys
import time
import urllib.request

API_KEY = os.environ.get("DOUBAO_API_KEY")
BASE_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
MODEL = "doubao-seed-2-0-lite-260428"
BOOK = os.path.join(os.environ.get("TEMP", "."), "book_compressed.jpg")

PROMPT_OLD = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"所在句子(可选)"}]}'
    "要求：单词给词性，短语/句子给翻译。无标记返回{\"items\":[]}。只输出JSON。简洁思考。"
)

CASES = [
    ("book_old_prompt_low", {"thinking": {"type": "enabled"}, "reasoning_effort": "low"}),
    ("book_old_prompt_high", {"thinking": {"type": "enabled"}, "reasoning_effort": "high"}),
    ("book_old_prompt_minimal", {"thinking": {"type": "enabled"}, "reasoning_effort": "minimal"}),
]


def run(name: str, extra: dict) -> dict:
    with open(BOOK, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    body = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": PROMPT_OLD},
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
    req = urllib.request.Request(
        BASE_URL,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.time()
    first_content = first_reasoning = None
    reasoning_chars = content_chars = 0
    content_text = ""
    try:
        with urllib.request.urlopen(req, timeout=150) as resp:
            for raw in resp:
                line = raw.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                try:
                    d = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                for ch in d.get("choices") or []:
                    delta = ch.get("delta") or {}
                    c = delta.get("content")
                    r = delta.get("reasoning_content")
                    if c:
                        if first_content is None:
                            first_content = time.time() - t0
                        content_chars += len(c)
                        content_text += c
                    if r:
                        if first_reasoning is None:
                            first_reasoning = time.time() - t0
                        reasoning_chars += len(r)
        out = {
            "name": name,
            "total_s": round(time.time() - t0, 1),
            "first_content_s": round(first_content, 1) if first_content else None,
            "reasoning_chars": reasoning_chars,
            "has_ellipsis": "…" in content_text or "..." in content_text,
        }
        fname = os.path.join(os.environ.get("TEMP", "."), f"c4_{name}.txt")
        with open(fname, "w", encoding="utf-8") as f:
            f.write(content_text)
        return out
    except Exception as e:
        return {"name": name, "total_s": round(time.time() - t0, 1), "error": str(e)}


def main():
    for name, extra in CASES:
        print(f"=== {name} ...", flush=True)
        r = run(name, extra)
        print(f"    {json.dumps(r, ensure_ascii=False)}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
