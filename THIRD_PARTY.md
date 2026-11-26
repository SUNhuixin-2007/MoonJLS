# 来源、移植与授权

## CharLS 的范围移植

本工程不是“全部原创算法”，也不是 libcharls 包装器。JPEG-LS 编码核心基于 [CharLS](https://github.com/team-charls/charls) **2.4.2** 的公开实现进行范围移植，固定上游提交为 `36dd3307e070d8fbc765c3ba890b7e681046fa39`。

CharLS 采用 BSD-3-Clause。原始版权与完整许可保存在 [docs/CHARLS-LICENSE.md](docs/CHARLS-LICENSE.md)，项目根 [LICENSE](LICENSE) 保留上游版权并为本项目新增工作使用相同许可。各移植文件头应标注 CharLS 来源与 SPDX；不能删除上游版权或宣称得到其作者背书。

| 上游职责 | MoonBit 适配范围 |
| --- | --- |
| `default_traits.h` / 样本模型 | 精度、MAXVAL、NEAR、RANGE、误差量化与重建约束 |
| `jpegls_preset_coding_parameters.h` | 默认 T1/T2/T3、RESET 与显式参数验证 |
| regular-mode context | A/B/C/N 统计、Golomb 参数和预测偏差演化 |
| run-mode context | N/Nn/A 统计、run interruption 映射与更新 |
| `scan.h` / codec | 邻域预测、regular/run 切换、分量交织及样本重建的选定路径 |
| `jpeg_stream_writer.cpp` / `validate_spiff_header.cpp` | SPIFF v2 header、色彩空间/分量/分辨率校验与写出 |
| `color_transform.h` | 可逆整数域 HP1/HP2/HP3 变换公式 |

MoonBit 的数据类型、错误模型、受限位流、容器解析与写出、图像操作、JSON/PNM 交换、宿主适配、测试和文档属于本次工程工作。此表说明的是算法和设计来源，具体有效范围仍以 `docs/COMPATIBILITY.md`、源文件和测试为准；没有将 CharLS 所有代码和平台功能全量移植。

原仓库克隆在忽略目录 `work/charls`，不作为本项目源代码分发，不计入核心行数。若后续引入更多上游文件或改变移植范围，应更新本表和相应文件版权。

## 标准与验证依赖

- [ITU-T T.87](https://www.itu.int/rec/T-REC-T.87/en)，对应 ISO/IEC 14495-1:1999：用于核对 JPEG-LS baseline 的标记、预测和编码语义。仅引用链接，不把标准全文作为项目自有文档分发。
- T.87 官方附件 JPEG-LS Reference Software V1.00X（1999-03-04）：仅用于本项目的标准符合性测试，包含 HP/ISO/IEC/ITU 的测试用途许可，**不是 BSD 产品代码**。原始软件、许可、PDF 和官方图集保存在忽略的 `work/standards`，不随本库分发。`scripts/t87_interop.py` 记录官方来源及逐个 EXE 的摘要；公开 `fixtures/t87-maxval` 是本项目自建合成输入产生的验证向量。参考程序 MAXVAL=1/2 及低 MAXVAL 近无损隐式默认值的限制在 [MAXVAL_EVIDENCE.md](docs/MAXVAL_EVIDENCE.md) 单列。
- [imagecodecs](https://github.com/cgohlke/imagecodecs) **2026.11.11**：BSD-3-Clause，独立验证依赖；其 JPEG-LS 模块调用所附 CharLS。实际 CharLS 和 NumPy 版本由运行记录获取，不从版本名称猜测。
- NumPy：BSD-3-Clause，用于在独立验证脚本中构造和比较整数图像。
- MoonBit 标准库：Apache-2.0，以工具链随附版本及 `moon.pkg` 实际导入为准。
- `scripts/count_loc.py`、`scripts/validate.py` 与 Node 文件宿主的 I/O/安全创建结构：复用并适配本地 MoonDLT 工程的通用工程代码；未复用 DLT 领域实现，辅助脚本不计核心代码量。

Python 与原生 CharLS 仅用于开发验证，不是编译后 MoonBit 核心的运行时依赖。安装内容位于忽略的 `work/pydeps`，不与核心源代码混计。

## 测试数据与 AI

`fixtures/` 使用本项目公开定义的合成样本：常量、渐变、棋盘、重复游程和确定性伪随机值。由独立 CharLS 或官方 T.87 参考程序编码生成码流，记录原样本、重建值及摘要；没有将官方符合性图集、患者数据、企业图像或外部真实日志并入公开向量。

AI 参与了检索、移植适配、接口、测试和文档。标准与上游实现才是算法依据；AI 输出仍须通过类型检查、标准字段核对和独立互操作。维护者应能够解释状态更新、位流边界、误差保证与不支持项，不把 AI 生成本身当作正确性证据。

原始图像交换格式依据 [Netpbm PNM](https://netpbm.sourceforge.net/doc/pnm.html) 与 [PAM](https://netpbm.sourceforge.net/doc/pam.html)。开发期间曾用本机 FFmpeg 对非满范围 MAXVAL 做探索性解码，结果未计入通过向量；项目没有复制其源码或分发 FFmpeg。
