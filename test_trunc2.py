# -*- coding: utf-8 -*-
"""压缩路径实验:App 把大照片压到 2048px+q75 再发——对比压缩版 vs 原图高清版,
看压缩是否导致模型词条化截断。用法: python test_trunc2.py [图片路径]
"""
import base64
import json
import os
import sys
import time
import urllib.request
from PIL import Image

API_KEY = os.environ.get("DOUBAO_API_KEY")
BASE = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
SRC = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\xi283\Downloads\IMG_20240828_085847.jpg"
TMP = os.environ["TEMP"]

# 与 App 完全一致的压缩:最长边 2048 + JPEG q75
im = Image.open(SRC).convert("RGB")
w, h = im.size
scale = 2048 / max(w, h)
im_comp = im if scale >= 1 else im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
p_comp = os.path.join(TMP, "t_comp.jpg")
im_comp.save(p_comp, "JPEG", quality=75)
# 原图高清对照(仅转 JPEG q92,不做缩放)
p_raw = os.path.join(TMP, "t_raw.jpg")
im.save(p_raw, "JPEG", quality=92)
print("原图", im.size, "→ 压缩", im_comp.size, "| 压缩体积", os.path.getsize(p_comp) // 1024, "KB | 原图", os.path.getsize(p_raw) // 1024, "KB")

SYSTEM = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"完整原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"完整句子(短语/句子必填,单词可选)"}]}'
    "要求：1.word 必须与照片中的文本完全一致——单词、短语、句子一律完整输出,"
    "禁止截断,禁止用省略号(…)代替后半部分。2.短语/句子必须在 original_sentence 中"
    "给出其所在的完整句子(必填,不可省略)。3.单词给词性。无标记返回{\"items\":[]}。"
    "只输出JSON。简洁思考。"
)


def run(name, img_path, model, extra):
    with open(img_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM},
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
        BASE,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.time()
    content = ""
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
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
                ch = (d.get("choices") or [{}])[0].get("delta") or {}
                c = ch.get("content")
                if c:
                    content += c
    except Exception as e:
        print(name, "ERR", e)
        return
    dt = time.time() - t0
    try:
        items = json.loads(content)["items"]
    except Exception as e:
        print(name, f"{dt:.1f}s PARSE FAIL: {e} | {content[:150]}")
        return
    trunc = [it["word"] for it in items if "…" in it["word"] or it["word"].endswith("...")]
    print(f"== {name}  {dt:.1f}s  items={len(items)}  截断={len(trunc)}")
    for it in items[:12]:
        w_ = it["word"]
        flag = "  <--截断" if ("…" in w_ or w_.endswith("...")) else ""
        print(f"   [{it.get('word_type','?')}] {w_}{flag}")
    print()


run("turbo_压缩2048q75 ", p_comp, "doubao-seed-2-1-turbo-260628", {"thinking": {"type": "disabled"}})
run("turbo_原图q92     ", p_raw, "doubao-seed-2-1-turbo-260628", {"thinking": {"type": "disabled"}})
run("lite_压缩2048q75  ", p_comp, "doubao-seed-2-0-lite-260428", {"thinking": {"type": "disabled"}})
run("lite_原图q92      ", p_raw, "doubao-seed-2-0-lite-260428", {"thinking": {"type": "disabled"}})
