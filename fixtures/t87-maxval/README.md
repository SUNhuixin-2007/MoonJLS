# 非满范围 MAXVAL 独立验证向量

这里仅分发本项目定义的合成整数输入、由独立参考程序产生的码流/重建值和验证摘要，不分发官方程序或 Annex E 官方图像。

参考工具来自 ITU-T T.87 标准附带软件中的 jlsrefV100.zip，Windows PE V1.00X，1999-03-04。原包及各可执行文件 SHA-256 在 golden.json 中固定。原工具许可仅允许标准符合性测试，程序、版权与原许可均留在忽略的 work/，不能按本项目 BSD 许可证再分发。

## 覆盖

144 组灰度向量，MAXVAL 为 3、15、31、100、128、255、256、1000、1024、4095、4096、65534，含 NEAR=0、合法 1/3 与上界、阶跃/渐变/确定性噪声和窄行边界。参考工具不接受 MAXVAL=1/2，这两种边界由标准推导测试另行验证，不计入此工具的独立通过数量。

旧参考程序在 MAXVAL<128、NEAR>0 时的隐式默认阈值分支与最终 T.87 C.5 不同。因此相应向量使用明确写入 LSE 的合法自定义阈值及 RESET=64；不会把这些旧隐式默认码流当作规范黄金。MAXVAL>=128（包括重点 MAXVAL=1000）保留标准默认预设。

## 复现

```sh
python scripts/t87_interop.py --require-reference
python scripts/t87_interop.py --golden-only
python scripts/t87_interop.py --annex-e-only --require-reference
```

默认先核对已提交参考字节和 SHA，再让 MoonJLS 解码并比较全部样本。Windows 下存在并通过哈希校验的官方 PE 时，还执行 MoonJLS 编码→官方解码，并与 MoonJLS 解码结果逐样本比较，校验最大误差。Linux/macOS CI 的 `--golden-only` 只宣称固定官方输入解码通过，不冒充现场外部解码验证。

黄金输入只在显式 `--generate-fixtures` 时重写。`--record-output-examples` 须完整现场双向检查通过，才写入两个 MAXVAL=1000 的输出例证及独立解码收据。

## 可检查案例

`examples/max1000-near0-*` 与 `max1000-near3-*` 分别给出输入 PGM、官方 JLS、官方重建 PGM、MoonJLS 输出 JLS 和官方对 MoonJLS 输出的重建 PGM。`output-verification.json` 包含逐文件摘要、误差和参考程序身份。

Annex E 测试仅从 work/ 中读取官方资料，输出 PASS/KNOWN_GAP/FAIL 矩阵到 work/validation/t87-annex-e.json。现场结果为 10 项解码 PASS、2 项异采样 KNOWN_GAP，汇总 PARTIAL。报告明确标记 decode-only、encoder_conformance=NOT_RUN，不能将解码样本验证等同于第 8.2 节的编码器符合性检查。

官方图包 README 将 T8NDE0/3 描述为 TEST8 RGB，但实际文件为 128×128 灰度，对应原始 PGM 没有随包分发。这两项逐像素对照官方解码器，并用配套 E0 无损重建检查 E3 的误差界，报告保留这一来源限制。显式不支持的异采样用例不会计为通过；参考工具本身也注明其实现不覆盖标准全部语法，因此这些结果不是完整标准认证。
