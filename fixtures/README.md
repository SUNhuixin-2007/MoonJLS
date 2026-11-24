# CharLS 黄金向量

`charls-golden.json` 含 282 组公开合成输入、CharLS 字节、SHA-256 与独立重建样本。生成引擎为 imagecodecs 2026.11.11 所附 CharLS 2.4.5；`gray8.jls` 是同组语料中的一个 8 位灰度输入。

默认 `python scripts/interop.py` 核对已提交清单，失败不会自动修订预期值。仅在有意更改覆盖范围或参考版本时执行：

```sh
python scripts/interop.py --generate-fixtures
```

应审查向量差异后提交。`--quick` 只用于快速开发核对，不替代完整验证；不要与黄金生成参数合用。数据全部由 `scripts/interop.py` 定义的整数公式合成，无外部患者、商业图像或版权不明的标准测试图。向量和生成接口不计入有效核心代码。
