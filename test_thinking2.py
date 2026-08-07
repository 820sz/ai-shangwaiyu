# -*- coding: utf-8 -*-
"""第二轮实测:reasoning_effort 是否控制豆包思考时长 + 模型输出是否自带省略号截断。
保存完整 content 到文件供检查。不打印 API key。
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
IMAGE_PATH = os.path.join(os.environ.get("TEMP", "."), "shot_v114.jpg")

SYSTEM_PROMPT = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"所在句子(可选)"}]}'
    "要求：单词给词性，短语/句子给翻译。无标记返回{\"items\":[]}。只输出JSON。简洁思考。"
)

VARIANTS = {
    "A_reasoning_effort_minimal": {"thinking": {"type": "enabled"}, "reasoning_effort": "minimal"},
    "B_reasoning_effort_low": {"thinking": {"type": "enabled"}, "reasoning_effort": "low"},
    "C_reasoning_effort_high": {"thinking": {"type": "enabled"}, "reasoning_effort": "high"},
    "D_disabled_control": {"thinking": {"type": "disabled"}},
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
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.time()
    first_byte = first_content = first_reasoning = None
    reasoning_chars = content_chars = 0
    content_text = ""
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
        elapsed = time.time() - t0
        out = {
            "name": name,
            "total_s": round(elapsed, 1),
            "first_content_s": round(first_content, 1) if first_content else None,
            "first_reasoning_s": round(first_reasoning, 1) if first_reasoning else None,
            "reasoning_chars": reasoning_chars,
            "content_chars": content_chars,
        }
        # 保存 content 供省略号检查
        fname = os.path.join(os.environ.get("TEMP", "."), f"content_{name}.txt")
        with open(fname, "w", encoding="utf-8") as f:
            f.write(content_text)
        out["saved_to"] = fname
        out["has_ellipsis"] = "…" in content_text
        return out
    except Exception as e:
        return {"name": name, "total_s": round(time.time() - t0, 1), "error": str(e)}


def main():
    results = []
    for name, extra in VARIANTS.items():
        print(f"=== {name} ...", flush=True)
        r = run(name, extra)
        results.append(r)
        print(f"    {json.dumps(r, ensure_ascii=False)}", flush=True)
    print("\n===== 汇总 =====")
    for r in results:
        print(json.dumps(r, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
