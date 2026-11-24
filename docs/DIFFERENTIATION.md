# 生态差异与检索证据

检索日期：2026-11-23。目标是比较已经公开的实际能力，不能据此证明所有未公开申报都没有相邻内容。

## 核心独立贡献

MoonJLS 的核心输入输出是 JPEG-LS baseline 码流与 2–16 位整数图像。技术工作是 LOCO-I 邻域预测、适应性上下文与 Golomb 熵编码，以及同一预测历史上的近无损重建。它不是把已有图像库改名，也不是只检查图像头后输出质量或风险报告。

迁移理由是部署与数据语义：MoonBit/Wasm/JS 消费者无需部署 C++ 编译产物即可处理标准 JPEG-LS；图像样本保持整数精度，误差由 `NEAR` 明确约束，而不是统一降为 8 位 RGBA。

## 相近项目逐项比较

| 公开项目 | 核查到的范围 | MoonJLS 的区别 |
| --- | --- | --- |
| [mizchi/image-mbt](https://github.com/mizchi/image-mbt) | main 分支 README：JPEG 是 8 位 Huffman DCT baseline、extended sequential、progressive；明确列出 lossless JPEG 等不支持项 | JPEG-LS 使用 SOF55、邻域预测、regular/run 上下文与 Golomb 编码；不能由 DCT JPEG 支持推导其支持 JPEG-LS |
| [moonbitstack/moonimage](https://github.com/moonbitstack/moonimage) | master 分支 README：JPEG baseline/progressive；源码目录未见 JPEG-LS/CharLS/LOCO 路径 | MoonJLS 补充独立 JPEG-LS 编码标准，不重做该库的 PNG/JPEG/WebP 图像集合 |
| [walkzzz/image.mbt](https://github.com/walkzzz/image.mbt) | main 分支 README：JPEG baseline 与 JPEG XL 分别列出；源码目录未见 JPEG-LS/CharLS/LOCO 路径 | JPEG XL 与 JPEG-LS 的格式和算法不同，名称同含 JPEG 不构成可互换实现 |
| [gmlewis/moonbit-image](https://github.com/gmlewis/moonbit-image) | JPEG 包公开描述为 8 位 baseline/progressive；源码目录未见 JPEG-LS 路径 | 不提供已查到的 JPEG-LS 基线算法 |
| [suica/jxl](https://github.com/suica/jxl.mbt) | JPEG XL 解码器 | JXL 与 T.87 JPEG-LS 不互换 |
| [trkbt10/jpeg2000](https://github.com/trkbt10/jpeg2000_mbt) | T.800 JPEG 2000 解码器 | JPEG 2000 的小波/块编码与 JPEG-LS 的预测编码不同；本工程不重做 J2K |
| [CCllff-jpg/moondicom](https://mooncakes.io/docs/CCllff-jpg/moondicom) | DICOM Part 10 元数据解析、验证、匿名化和 JSON | MoonJLS 只编解码图像压缩码流，不提供 DICOM 文档、匿名化或临床解释；可成为文档库的独立 codec |
| 本地 MoonDLT | ECU 应用日志二进制协议与筛选 | 领域模型、算法、数据结构均不同；没有把日志容器换皮成图像项目 |

`riantr/moonbit_image` 的 Mooncakes 公开描述列出多种常见格式，未列 JPEG-LS；其所链接 GitHub 仓库在本次访问时返回 404，无法核验源码，因此不把它当作已经完成源码排重的证据。

## 检索方法

```sh
moon search jpegls --limit 6
moon search charls --limit 6
moon search jpeg --limit 8
```

同时对 MoonBit 与 `JPEG-LS`、`JPEG LS`、`LOCO-I`、`CharLS` 的组合做网页检索，并读取上表相关仓库的真实默认分支、README 和源码目录。精确关键词未找到直接实现，模糊结果主要是已有 DCT JPEG/JPEG XL/JPEG 2000 包。源码目录检查只能说明当时公开树中没有对应路径，不能证明其每行代码都不存在相关未命名实现。

如审核方提供直接重合项目，应比较实际算法、样本精度、NEAR、交织、资源预算与测试证据，再决定给现有项目贡献或缩减独立范围，不能仅用“Wasm”“高性能”“工具包”等名称宣称区别。

## 其他语言成熟实现

[CharLS](https://github.com/team-charls/charls) 已长期提供 JPEG-LS 编解码，BSD-3-Clause。MoonJLS 不宣称发明 JPEG-LS，而是说明其选定算法如何迁移、哪些平台约束被解除、如何验证兼容。独立 imagecodecs/CharLS 的像素交叉验证比单纯 encode/decode 自身往返更能证明实际价值。
