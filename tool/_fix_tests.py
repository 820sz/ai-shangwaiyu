# -*- coding: utf-8 -*-
p = r"test/find_material_ai_rewrite_test.dart"
s = open(p, encoding="utf-8").read()
reps = [
    ("expect(prompt.system, contains('不是原文'));", "expect(prompt.system, contains('非原文'));"),
    ("expect(prompt.system, contains('不许编造具体引文'));", "expect(prompt.system, contains('禁止编造'));"),
    ("expect(prompt.system, contains('禁止编造链接'));", "expect(prompt.system, contains('禁止编造'));"),
    ("expect(prompt.system, contains('先确定作品/主题'));", "expect(prompt.system, contains('原作者的叙述口吻'));"),
    ("expect(prompt.system, contains('不设固定字数'));", "expect(prompt.system, contains('篇幅由原材料内容量决定'));"),
    ("expect(prompt.user, contains('覆盖全部要点'));", "expect(prompt.user, contains('覆盖完整内容的英文学习版'));"),
    ("expect(prompt.user, contains('这次没有可用线索'));", "expect(prompt.user, contains('没有外部线索'));"),
    ("expect(prompt.user, contains('这次没有可用线索'));", "expect(prompt.user, contains('没有外部线索'));"),
]
for old, new in reps:
    s = s.replace(old, new)
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("tests updated")