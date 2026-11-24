# MoonJLS：面向 Wasm 的 JPEG-LS 无损与近无损图像编码库

**申请人与仓库**：孙卉欣（GitHub：[SUNhuixin-2007](https://github.com/SUNhuixin-2007)）；项目仓库：[https://github.com/SUNhuixin-2007/MoonJLS](https://github.com/SUNhuixin-2007/MoonJLS)。Mooncakes：`SHX-ai-nb/moonjls@0.1.0`；GitHub 改名后 Mooncakes 保留旧用户名。

**问题与消费者**：MoonBit 图像工具需要直接处理科研灰度与多通道 2–16 位整数样本，同时能够选择严格无损或有明确逐样本误差上限的压缩。普通 8 位 DCT JPEG、JPEG XL 和 JPEG 2000 不是 JPEG-LS 标准的互换实现；把数据降为 RGBA8 会丢失原有样本信息。

**交付与边界**：以 ITU-T T.87 / ISO/IEC 14495-1 为基准，移植 CharLS 的 regular/run 模式与上下文算法到纯 MoonBit，提供 JPEG-LS 码流读写、2–16 位图像模型、`NEAR` 参数、交织、自定义阈值/RESET、DRI 重启、LSE4 大尺寸、SPIFF/HP 扩展、按行接口与真实 PNM/PAM 文件工具。首版 MAXVAL 限定为满位深范围，两通道交织仅有本地验证，外部互操作范围单列；不承诺 Part 2、完整 DICOM、厂商私有变换或受损图像自动恢复。

**技术路线**：按 SOI/SOF55/LSE/SOS/EOI 分离标记与熵编码段；用重建邻域而非原始邻域决定预测和上下文。regular 模式执行梯度量化、符号归一、偏差修正和受限 Golomb 编码；run 模式处理平坦区域长度与中断样本。16 位模运算、`NEAR` 误差量化和状态重置均对照上游与标准，避免编码器和解码器产生不同预测历史。尺寸乘法、位读取、压缩输出及元数据保留受显式预算控制。

**迁移价值**：已有 CharLS 是成熟 C++ 库。MoonJLS 将选定核心算法与位流适配为统一 MoonBit 接口，使 Wasm/JS 工具无需编译和部署 C FFI 即可读写现成 JPEG-LS 数据；不要求现有桌面工具迁移，也不声称超越上游全部性能和功能。

**生态区别**：检索并核查 mizchi/image-mbt、moonbitstack/moonimage、walkzzz/image.mbt 等实际公开职责，它们的 JPEG 主要是 DCT baseline/progressive；现有 JXL 与 JPEG 2000 是另外两种编码标准。MoonDICOM 处理 DICOM 文档，MoonJLS 只处理压缩图像码流。当前多关键词检索未发现直接 MoonBit JPEG-LS 实现；这不是对未公开申报的保证。链接、日期和不确定性见 `docs/DIFFERENTIATION.md`。

**规模与验证**：生产核心严格有效 MoonBit 代码 4,100 行（非空非注释 5,153 行），测试、示例、向量和依赖单列。以固定版本 imagecodecs/CharLS 双向交叉验证各精度、平坦/渐变/边界/随机样本、`NEAR=0` 精确像素与 `NEAR>0` 最大绝对误差；三种运行目标各 42 项测试，另测畸形标记、全部截断、超预算及元数据，并用真实文件工具验证消费者路径。Windows 原生运行未验证，远程 CI 与发布结果见 `docs/SUBMISSION_STATUS.md`。提供跨目标检查、可运行示例、代码统计、CI 和本地证据，不以自测往返代替外部互操作。

**来源与后续**：CharLS 2.4.2，提交 `36dd3307e070d8fbc765c3ba890b7e681046fa39`，BSD-3-Clause，保留版权与完整许可。移植范围、MoonBit 适配和 AI 辅助在 `THIRD_PARTY.md` 披露。按最新官方通知完成比赛报名材料；本地首版不等于量产集成或标准认证。
