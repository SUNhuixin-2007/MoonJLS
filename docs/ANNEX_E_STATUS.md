# 官方附件码流的当前解码状态

2026-11-26 对 T.87 附件 `jlsimgV100.zip` 中全部 12 个 JLS 文件运行本项目真实文件工具，并与官方解码器逐样本比较：**10 个解码通过、2 个异采样缺口，汇总 PARTIAL**。这是解码方向的阶段记录；编码器第 8.2 节符合性测试未运行，不能称完整编解码符合。

| 组号 | 文件 | 当前结果 |
| --- | --- | --- |
| 1–6 | T8C0E0/3、T8C1E0/3、T8C2E0/3 | 解码样本与官方参考一致；覆盖无损/NEAR=3 与三种交织 |
| 7–8 | T8SSE0/3 | KNOWN_GAP：异采样分量尚不支持，明确拒绝并清理本次输出 |
| 9–10 | T8NDE0/3 | 解码样本与官方参考一致；原始图缺失，来源限制如下 |
| 11–12 | T16E0/3 | 16 位解码样本与官方参考一致 |

该 ZIP 的 README 将 T8NDE0/3 记为 TEST8 RGB，但实际码流是 128×128 灰度，且匹配的原始 PGM 未随包提供。这两项按真实码流和官方解码输出比较，NEAR=3 的误差以配套 E0 无损重建为基准；不能声称已获得缺失的原图或完全执行文档所述输入过程。

逐项 SHA、方向、时间及结果见 [T87_ANNEX_E_VALIDATION.json](T87_ANNEX_E_VALIDATION.json)。软件和图包仅保存在忽略的 `work/standards`；报告不含原始官方图像。按 [MAXVAL_EVIDENCE.md](MAXVAL_EVIDENCE.md) 准备参考程序，再将官方 `jlsimgV100.zip` 提取到 `work/standards/jlsimgV100` 后可复现：

```sh
python scripts/t87_interop.py --annex-e-only --require-reference
```

最终验收将补齐异采样、编码器符合性和图包来源问题，并执行图集未覆盖的标准机制专项测试，详见 [BASELINE_PLAN.md](BASELINE_PLAN.md)。当前 10 个文件的解码通过不替代该最终目标。
