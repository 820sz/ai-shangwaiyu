# -*- coding: utf-8 -*-
"""第三轮实测:
1) 改 prompt(禁省略号)是否消除思考模式的 word 截断——同图同思考配置,对比新旧 prompt
2) 真实书本照片下 minimal vs low 的质量与耗时
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
MODEL = "doubao-seed-2-0-lite-260428"

PROMPT_OLD = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"所在句子(可选)"}]}'
    "要求：单词给词性，短语/句子给翻译。无标记返回{\"items\":[]}。只输出JSON。简洁思考。"
)

PROMPT_NEW = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"所在句子(可选)"}]}'
    "要求：单词给词性，短语/句子给翻译。无标记返回{\"items\":[]}。只输出JSON。"
    "重要：word 字段必须逐字完整输出原文，短语和句子禁止截断、禁止使用省略号。"
)

def shot_path():
    return os.path.join(os.environ.get("TEMP", "."), "shot_v114.jpg")


def book_path():
    # 先用压缩后的书本照片(不存在则用截图)
    p = os.path.join(os.environ.get("TEMP", "."), "book_compressed.jpg")
    return p if os.path.exists(p) else shot_path()


def build_body(image_path: str, extra: dict, system_prompt: str) -> dict:
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    mime = "image/jpeg"
    body = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}", "detail": "low"}},
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


def run(name: str, image_path: str, extra: dict, system_prompt: str) -> dict:
    body = build_body(image_path, extra, system_prompt)
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
        elapsed = time.time() - t0
        out = {
            "name": name,
            "total_s": round(elapsed, 1),
            "first_content_s": round(first_content, 1) if first_content else None,
            "reasoning_chars": reasoning_chars,
            "content_chars": content_chars,
            "has_ellipsis": "…" in content_text or "..." in content_text,
        }
        fname = os.path.join(os.environ.get("TEMP", "."), f"c3_{name}.txt")
        with open(fname, "w", encoding="utf-8") as f:
            f.write(content_text)
        out["saved_to"] = fname
        return out
    except Exception as e:
        return {"name": name, "total_s": round(time.time() - t0, 1), "error": str(e)}


def main():
    shot = shot_path()
    book = book_path()
    CASES = [
        ("1_prompt_old_low", shot, {"thinking": {"type": "enabled"}, "reasoning_effort": "low"}, PROMPT_OLD),
        ("2_prompt_new_low", shot, {"thinking": {"type": "enabled"}, "reasoning_effort": "low"}, PROMPT_NEW),
        ("3_prompt_new_minimal", book, {"thinking": {"type": "enabled"}, "reasoning_effort": "minimal"}, PROMPT_NEW),
        ("4_prompt_new_low_book", book, {"thinking": {"type": "enabled"}, "reasoning_effort": "low"}, PROMPT_NEW),
        ("5_prompt_new_disabled_book", book, {"thinking": {"type": "disabled"}}, PROMPT_NEW),
    ]
    results = []
    for name, img, extra, sp in CASES:
        print(f"=== {name} ...", flush=True)
        r = run(name, img, extra, sp)
        results.append(r)
        print(f"    {json.dumps(r, ensure_ascii=False)}", flush=True)
    print("\n===== 汇总 =====")
    for r in results:
        print(json.dumps(r, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
