# -*- coding: utf-8 -*-
"""第八轮:detail=high 是否让模型完整输出长句子 word。不打印 API key。
"""
import base64
import json
import os
import time
import urllib.request

API_KEY = os.environ.get("DOUBAO_API_KEY")
BASE_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
MODEL = "doubao-seed-2-0-lite-260428"
IMG = os.path.join(os.environ.get("TEMP", "."), "clean_sentence.png")

PROMPT_NEW = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"所在句子(可选)"}]}'
    "要求：单词给词性，短语/句子给翻译。无标记返回{\"items\":[]}。只输出JSON。"
    "重要：word 字段必须逐字完整输出整句原文，禁止截断、禁止省略号、禁止省略任何单词；"
    "translation 必须完整翻译，禁止用省略号代替任何内容。句子很长也必须完整。"
)


def run(name: str, extra: dict, detail: str) -> dict:
    with open(IMG, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    body = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": PROMPT_NEW},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}", "detail": detail}},
                    {"type": "text", "text": "识别图中被标记的英语内容"},
                ],
            },
        ],
        "max_tokens": 4096,
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
                    if c:
                        content_text += c
        return {
            "name": name,
            "total_s": round(time.time() - t0, 1),
            "output": content_text.strip()[:600],
        }
    except Exception as e:
        return {"name": name, "total_s": round(time.time() - t0, 1), "error": str(e)}


def main():
    for detail in ["low", "high"]:
        print(f"=== detail={detail} disabled ===", flush=True)
        print(json.dumps(run(f"detail_{detail}", {"thinking": {"type": "disabled"}}, detail), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
