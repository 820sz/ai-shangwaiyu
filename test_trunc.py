# -*- coding: utf-8 -*-
"""词条截断回归定位实验:同提示词+同图,对比 模型×思考参数 4 组,
看 word 字段是否被模型词条化截断(~20字符+"…")。不打印 API key。"""
import base64
import json
import os
import time
import urllib.request
from PIL import Image

API_KEY = os.environ.get("DOUBAO_API_KEY")
BASE = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
SRC = os.path.join(os.environ["TEMP"], "marked_page.jpg")  # 07-23 截图裁剪出的带标记书页
TMP = os.path.join(os.environ["TEMP"], "trunc_test.jpg")

# 按 App 逻辑压缩:最长边 2048,JPEG q75
im = Image.open(SRC).convert("RGB")
im.thumbnail((2048, 2048), Image.LANCZOS)
im.save(TMP, "JPEG", quality=75)

# 与 App v1.2.16 完全一致的提取提示词
SYSTEM = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"完整原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"完整句子(短语/句子必填,单词可选)"}]}'
    "要求：1.word 必须与照片中的文本完全一致——单词、短语、句子一律完整输出,"
    "禁止截断,禁止用省略号(…)代替后半部分。2.短语/句子必须在 original_sentence 中"
    "给出其所在的完整句子(必填,不可省略)。3.单词给词性。无标记返回{\"items\":[]}。"
    "只输出JSON。简洁思考。"
)


# v1.2.15 旧提示词:word 只写"原文",无禁止截断要求
SYSTEM_OLD = (
    "你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式："
    '{"items":[{"word":"原文","translation":"中文释义","word_type":"word|phrase|sentence",'
    '"part_of_speech":"词性(可选)","original_sentence":"所在句子(可选)"}]}'
    "要求：单词给词性，短语/句子给翻译。无标记返回{\"items\":[]}。只输出JSON。简洁思考。"
)


def run(name, model, extra, system=SYSTEM):
    with open(TMP, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
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
    for it in items[:14]:
        w = it["word"]
        os_ = it.get("original_sentence") or ""
        flag = "  <--截断" if ("…" in w or w.endswith("...")) else ""
        print(f"   [{it.get('word_type','?')}] {w}{flag} | 原句={'有' if os_ else '无'}")
    print()


run("lite_禁用思考  ", "doubao-seed-2-0-lite-260428", {"thinking": {"type": "disabled"}})
run("lite_低度思考  ", "doubao-seed-2-0-lite-260428", {"thinking": {"type": "enabled"}, "reasoning_effort": "minimal"})
run("turbo_禁用思考 ", "doubao-seed-2-1-turbo-260628", {"thinking": {"type": "disabled"}})
run("turbo_低度思考 ", "doubao-seed-2-1-turbo-260628", {"thinking": {"type": "enabled"}, "reasoning_effort": "minimal"})
