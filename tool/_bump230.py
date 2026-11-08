# -*- coding: utf-8 -*-
p = r"pubspec.yaml"
s = open(p, encoding="utf-8").read().replace("version: 2.29.2+100", "version: 2.30.0+101", 1)
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("bumped 2.30.0+101")