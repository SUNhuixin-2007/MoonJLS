# MoonJLS

[GitHub CI](https://github.com/SUNhuixin-2007/MoonJLS/actions/workflows/check.yml) · [Mooncakes](https://mooncakes.io/docs/SHX-ai-nb/moonjls)

MoonJLS 是 **纯 MoonBit JPEG-LS 无损与近无损图像编解码库**。它直接处理 2–16 位无符号样本，按 JPEG-LS 的预测、上下文统计和 Golomb 熵编码压缩图像；常见使用对象是科研灰度图、多通道原始图像和需要保留整数样本的 Wasm 工具。

项目由 [SUNhuixin-2007](https://github.com/SUNhuixin-2007) 维护，源码仓库为 [MoonJLS](https://github.com/SUNhuixin-2007/MoonJLS)。本地工程保存在 `D:\CodexProjects\MoonJLS`；Mooncakes 命名空间为 `SHX-ai-nb/moonjls`。GitHub 已从 SHX-ai-nb 改名为 SUNhuixin-2007，Mooncakes 保留原用户名，二者归属于同一个 GitHub 账号。项目范围见 [兼容性清单](docs/COMPATIBILITY.md)，选题与迁移价值见 [申报书](PROPOSAL.md) 和 [生态差异](docs/DIFFERENTIATION.md)。

## 实现方式

项目是 **CharLS 2.4.2 的 MoonBit 移植与工程适配**。最终目标是 **ITU-T T.87 / ISO/IEC 14495-1 完整 JPEG-LS 基线标准符合性**，当前实现、未完成事项和验收路线逐项列在 [基线目标](docs/BASELINE_PLAN.md)。移植保留成熟实现中 regular/run 模式的上下文演化和样本重建规则，采用 MoonBit 的位流、类型、错误和资源约束接口；编译后的核心不调用 CharLS、Python 或 C FFI。具体文件与来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。

JPEG-LS 与普通 JPEG 的核心方法不同：它按邻域中值预测样本、量化梯度选择上下文、适应性更新预测偏差，并使用 regular/run 两种编码路径。JPEG-LS 不使用普通 JPEG 的 DCT/量化质量参数，`NEAR` 明确限制每个样本允许的绝对误差。

## 本地运行

已验证工具链为 moonc `0.10.17+093cb8f9c`，CI 固定同版编译器和标准库。文件工具另需 Node.js 22+，开发用独立互操作脚本另需 Python；核心只依赖 MoonBit 标准库。

```sh
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon run cmd/demo --target js
moon fmt --check
```

原生运行需要平台 C 编译器与链接环境。各目标的最终实测结果以验证记录为准，不把静态检查等同于运行通过。

## 转换本地文件

以下命令会自动构建 MoonBit JS 宿主适配器。核心压缩与解压都在 MoonBit 中完成，Python/CharLS 不参与日常转换。

```sh
node scripts/moonjls.mjs encode input.pgm output.jls
node scripts/moonjls.mjs encode input.ppm output.jls --near 3 --interleave line
node scripts/moonjls.mjs inspect output.jls
node scripts/moonjls.mjs decode output.jls restored.pnm
node scripts/moonjls.mjs decode output.jls restored.pam --pam
```

输出必须是尚不存在的文件；失败会清理本次创建的部分输出。灰度/RGB 可用 PNM，Alpha 可用 PAM。二进制 P5/P6 编码按行读入；多分量 none 会回访输入并保留压缩输出。PAM/ASCII 编码及文件解码物化整图，报告如实标记。`inspect` 只检查结构，返回 `entropy_validated=false`；完整 `decode` 才验证熵数据与零填充。

v0.2.0 支持合法 `1 ≤ MAXVAL < 2^P`，不再沿用 v0.1.x 的满范围限制。PGM 的 MAXVAL=1000 会写为实际 LSE1.MAXVAL，不会改成 1023 或缩放像素。输入、双向码流、官方参考重建值见 [MAXVAL 证据](docs/MAXVAL_EVIDENCE.md)。两通道文件默认用 none，当前其它限制见兼容性表。

## 库接口

`Image.samples` 始终为逐行、像素交织的无符号整数数组，`bits_per_sample` 保留 2–16 位精度；输入码流采用何种交织方式，不改变库的样本布局。

```moonbit
let original : @jls.Image = {
  frame: { width: 2, height: 2, bits_per_sample: 12, components: 1 },
  samples: [0, 4095, 73, 2048],
}
let packed = @jls.encode(original)
let restored = @jls.decode(packed[:])
```

近无损编码使用 `EncodeOptions.near`。例如 `near=3` 的承诺是解码样本与原样本的绝对误差不超过 3，不是“质量 3”或平均误差。

```moonbit
let options = { ..@jls.EncodeOptions::default(), near: 3 }
let packed = @jls.encode(original, options~)
```

在自己的 `moon.pkg` 中导入 `"SHX-ai-nb/moonjls" @jls`；安装命令为 `moon add SHX-ai-nb/moonjls@0.2.0`。

## 独立验证

`imagecodecs==2026.11.11` 所附 CharLS 用于独立验证：先由 CharLS 写码流，再由 MoonJLS 解码；反方向由 MoonJLS 写码流，再由 CharLS 解码。比较的是样本数组和误差边界，压缩字节不要求与另一个合法编码器完全相同。

```sh
python -m pip install --target work/pydeps -r scripts/requirements-dev.txt
python scripts/interop.py
python scripts/t87_interop.py --golden-only
```

独立向量只使用公开合成图像；不含车辆日志、患者资料或商业图像。测试范围与限制见 [docs/VALIDATION.md](docs/VALIDATION.md)。一键复现完整本地检查：

```sh
python scripts/validate.py
```

记录包含三个运行目标各 50 项测试、CharLS 282 组双向与 80 组扩展、官方参考 144 组 MAXVAL 双向验证及 14 类真实文件场景。Linux CI 只核对已提交的官方黄金输入；Windows 现场双向证据另列，不能混计。Windows native 未执行，远程 CI 与发布进度见 [发布状态](docs/SUBMISSION_STATUS.md)。

## 源码规模

```sh
python scripts/count_loc.py
python scripts/count_loc.py --minimum 4000
```

统计将核心、测试、示例工具分开，排除依赖、构建、生成接口、注释和空行；严格口径进一步排除纯结构符号。当前严格有效核心为 **4,115 行**，非空非注释核心为 5,173 行。精确口径与逐文件统计保存在 [本地验证记录](docs/LOCAL_VALIDATION.json)，不承诺主办方采用相同计数方式。

## 资料与授权

- [技术路线](docs/TECHNICAL_DESIGN.md)：解释算法状态、码流边界、重建样本与资源预算。
- [完整基线目标](docs/BASELINE_PLAN.md) 与 [MAXVAL 输入输出证据](docs/MAXVAL_EVIDENCE.md)：说明首版限制、最终范围和阶段验收。
- [功能与限制](docs/COMPATIBILITY.md)：明确支持项与不支持项。
- [来源与移植范围](THIRD_PARTY.md)：上游版本、版权及依赖。
- [BSD-3-Clause](LICENSE)：项目许可；保留的 CharLS 原许可见 [docs/CHARLS-LICENSE.md](docs/CHARLS-LICENSE.md)。

本地实现和测试不代表获得 ITU、ISO、AUTOSAR 或医学用途认证。比赛报名表仍需按官方要求提交；仓库公开和模块发布不等于已经报名或通过审核。

本轮本地代码检查与修复明细见 [LOCAL_REVIEW.md](docs/LOCAL_REVIEW.md)。大尺寸 PNM 文件交换、预算边界和异常输入均有回归测试。
