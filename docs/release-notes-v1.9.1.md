## v1.9.1 — 紧急修复：v1.9.0 的识图/追问/文章/推荐全线不可用

**症状**（用户在真机实测发现）：识图直接失败，错误提示为

```
type 'Utf8Decoder' is not a subtype of type
'StreamTransformer<Uint8List, String>' of 'streamTransformer'
```

追问、AI 文章生成、材料推荐同样受影响（凡是走流式输出的功能）。

### 根因
v1.9.0 为修"中文被网络分包切开导致乱码"（审查项 P1-2），把 SSE 解析改成流式解码：

```dart
final lines = rawStream.transform(utf8.decoder).transform(const LineSplitter());
```

`rawStream` 的**声明**类型是 `Stream<List<int>>`，但 dio 的 `ResponseBody.stream`
在**运行时**是 `Stream<Uint8List>`。Dart 的 `Stream.transform` 会按接收者的实际类型参数
做检查，于是 `utf8.decoder`（`StreamTransformer<List<int>, String>`）被判为不是
`StreamTransformer<Uint8List, String>` → 运行时 `_TypeError`，整条流一行都读不出来。

**为什么单测没拦住**：当时测试用 `Stream<List<int>>.fromIterable(...)` 造流，
接收者的运行时类型参数是 `List<int>`，检查通过 —— 真机类型与测试类型不一致，
把这处缺陷测绿了。

### 修复
1. `parseSseStream` 里先 `rawStream.cast<List<int>>()` 再 `transform`（Dart 官方修法），
   4 个流式调用点（识图 / 追问 / 文章 / 推荐）全部经此解析器，一处修复全覆盖。
2. **测试改用 `Stream<Uint8List>` 造流**（`StreamController<Uint8List>` 与
   `Stream<Uint8List>.fromIterable`），并新增 2 条针对该真机报错的回归用例 ——
   修复前实测复现出与真机**逐字相同**的报错，修复后转绿。原有的 5 条 SSE 用例
   也一并改用真实流类型，避免同类问题再次"测绿"。

### 验证
- `flutter test`：**195 例全绿 + 1 skip**（v1.9.0 是 193）。
- `flutter analyze --no-fatal-infos`：0 error / 0 warning。
- 修复前后对照：把测试流类型换成 `Uint8List` 后，旧代码 5 条 SSE 用例全红且报错与真机一致 → 证明这条回归测试真的压在这个缺陷上。

> v1.9.0 的其余修复（数据迁移幂等、复习标记持久化、更新包校验、隐私收口等）都不受影响，本版只动 SSE 解码这一处。
