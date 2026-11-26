# 非满范围 MAXVAL 的输入、输出与独立验证

## 对本轮初审意见的直接补充

最终项目目标为 **ITU-T T.87 / ISO/IEC 14495-1 完整 JPEG-LS 基线标准符合性**；v0.1.x 的满范围限制是阶段选择，不是标准规定，也不保留为最终限制。[BASELINE_PLAN.md](BASELINE_PLAN.md) 列出完整范围、当前缺口、实现路线与验收门槛。本文证明本轮已补齐的 MAXVAL 能力，不宣称其余基线功能已经完成。

v0.2.0 公开编码、解码、按行接口和文件工具均接受合法 `1 ≤ MAXVAL < 2^P`，`P=2…16`。MAXVAL=0 的 preset 表示按 P 取默认值；显式 MAXVAL 保持原值，所有样本必须在 0…MAXVAL 内。`NEAR ≤ min(255,⌊MAXVAL/2⌋)`。例如 P=10、MAXVAL=1000 使用 RANGE=1001（NEAR=0）、bpp=10、qbpp=10、LIMIT=40，不能按 1023 构造模运算或掩码截断。

## 可下载的实际案例

固定合成灰度输入为 17×9，P=10、MAXVAL=1000；PGM 的 16 位存储按大端保存，每个样本保持原整数值。文件位于 [fixtures/t87-maxval/examples](../fixtures/t87-maxval/examples)。

| 配置 | 原始输入 | 外部编码的输入 JLS | 本库编码的输出 JLS | 官方程序解码本库输出 | 实测最大误差 |
| --- | --- | --- | --- | --- | --- |
| NEAR=0 | [PGM](../fixtures/t87-maxval/examples/max1000-near0-input.pgm) | [参考 JLS](../fixtures/t87-maxval/examples/max1000-near0-reference.jls) | [MoonJLS JLS](../fixtures/t87-maxval/examples/max1000-near0-moonjls.jls) | [重建 PGM](../fixtures/t87-maxval/examples/max1000-near0-moonjls-reference-decoded.pgm) | 0，全部 153 样本精确相等 |
| NEAR=3 | [PGM](../fixtures/t87-maxval/examples/max1000-near3-input.pgm) | [参考 JLS](../fixtures/t87-maxval/examples/max1000-near3-reference.jls) | [MoonJLS JLS](../fixtures/t87-maxval/examples/max1000-near3-moonjls.jls) | [重建 PGM](../fixtures/t87-maxval/examples/max1000-near3-moonjls-reference-decoded.pgm) | 3，全部 153 样本核查 |

前 17 个原始样本为：

```text
0,370,754,87,307,925,172,690,349,319,815,324,848,321,809,246,570
```

NEAR=0 的重建数组与之相同；NEAR=3 的独立重建前 17 样本为：

```text
0,371,756,85,309,927,172,692,350,322,818,321,845,318,807,247,570
```

JLS 中 SOF55.P=10，LSE1.MAXVAL=1000；NEAR=0 和 NEAR=3 的本库 JLS SHA-256 分别为 `125ea38574d90494ef2de44043362db82c361d7bbc2da80b9c444e528a209c95`、`749a052c15457a3d58384dc4a27fcc99a3060bc2378d10e9b9d8219a00eee4c6`。逐文件摘要、参考程序版本、程序摘要与执行时间见 [output-verification.json](../fixtures/t87-maxval/examples/output-verification.json)。本案例碰巧两种编码器压缩字节相同；一般验收不要求字节完全一致。

## 独立方法与实测范围

使用 [ITU 官方 T.87 页面](https://www.itu.int/rec/T-REC-T.87-199806-I/en) 附件中的 **JPEG-LS Reference Software V1.00X（1999-03-04）**，不是另写一份镜像算法。`jlsrefV100.zip` SHA-256 为 `085285f0552ef0b6ebcf29bc5a6d3bc0d6bda0408e9f2f1c138be2e55200814f`，8 个实际 EXE 摘要由脚本核验。

2026-11-26 在 Windows 执行：**144 组官方编码 → MoonJLS 解码通过，144 组 MoonJLS 编码 → 官方解码通过**。覆盖 MAXVAL=3/15/31/100/128/255/256/1000/1024/4095/4096/65534、阶跃/渐变/确定性噪声、NEAR=0/1/3/合法上限及窄图；其中 90 组为非满范围、54 组为满范围边界对照，不能把 144 组都称为非满范围。每组检查实际 MAXVAL、完整重建数组以及与原始输入的误差。完整参数和外部字节见 [golden.json](../fixtures/t87-maxval/golden.json)，现场报告见 [T87_MAXVAL_VALIDATION.json](T87_MAXVAL_VALIDATION.json)。

另外，MoonBit 本地测试分层覆盖 MAXVAL=1…65535 的代表值、1–4 分量、三种交织、P=16 但 MAXVAL=1000、重启及推送编码。官方独立矩阵为灰度；不能把多通道自身往返算作该 144 组的外部证据。

## 复现

无需安装官方程序即可核对提交的外部输入和重建值：

```sh
python scripts/t87_interop.py --golden-only
node scripts/moonjls.mjs inspect fixtures/t87-maxval/examples/max1000-near0-moonjls.jls
node scripts/moonjls.mjs decode fixtures/t87-maxval/examples/max1000-near0-reference.jls work/max1000-incoming.pgm
node scripts/moonjls.mjs encode fixtures/t87-maxval/examples/max1000-near0-input.pgm work/max1000-outgoing.jls
```

输出文件必须尚不存在。现场双向复现：从官方页面下载含软件的 ZIP，提取 `Software.zip` 中 `jlsrefV100.zip` 的文件到 `work/standards/jlsrefV100/`，保留原始 README/许可；在能运行其 EXE 的 Windows 上执行：

```sh
python scripts/t87_interop.py --require-reference
```

默认核对固定黄金清单，不重写预期值。`--generate-fixtures` 只用于明确审查的语料更新；`--record-output-examples` 另行记录输出案例。Linux CI 使用 `--golden-only`，只声明外部输入方向通过，现场输出方向为未运行。

## 参考实现限制与尚未完成事项

- 官方旧 EXE 拒绝 MAXVAL=1/2。本库保留这两个合法值，采用 T.87 推导的独立短码字（MAXVAL=1/2 的 `[0,MAXVAL] → A0`、MAXVAL=2 的 `[0,1] → B0` 熵字节）和域校验测试，明确不算作官方程序实测。
- 官方旧程序在 MAXVAL<128、NEAR>0 的隐式默认阈值与最终 T.87 C.5 不一致。此类测试显式写入合法自定义阈值和 RESET 的 LSE1；黄金清单保存具体值，不拿旧默认分支作为标准默认值的证据。MAXVAL=1000 等 ≥128 的案例保留正常默认阈值。
- 早期 CharLS 2.4.5/FFmpeg 的非满 MAXVAL 探索曾出现不一致结果，不能视为通过。新证据直接采用官方参考；原 CharLS 282 组双向与 80 组扩展矩阵仍限制为满范围，独立列报。
- 本轮不是完整基线验收。映射表/缩略格式、Pt、异采样、DNL 和部分宽字段/合法次序仍按 [最终矩阵](BASELINE_PLAN.md) 实现与验收；不得用本报告替代 Annex E 全 12 组及专项测试。

原始官方程序和官方图集仅用于符合性测试，保存在忽略目录，不随 BSD 库分发。公开案例全部由本项目合成输入产生，不包含官方测试图像或真实敏感图像。
