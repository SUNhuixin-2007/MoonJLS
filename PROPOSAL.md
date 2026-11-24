# MoonJLS 项目申报书

申请人：孙卉欣；GitHub：SUNhuixin-2007；Mooncakes：SHX-ai-nb（GitHub 改名前的注册名，属于同一账号）。

**1、项目名称**：MoonJLS——面向 MoonBit/Wasm 的 JPEG-LS 无损与近无损图像编解码库。

**2、项目简介**：针对 MoonBit 工具处理科研灰度图、工业原始图像时缺少 JPEG-LS 标准编解码组件的问题，将成熟 CharLS 的选定算法移植为纯 MoonBit 实现。直接读写 JPEG-LS 码流，保留 2–16 位无符号整数样本，NEAR=0 精确恢复，NEAR>0 给出逐样本绝对误差上限；核心不调用 C++、Python 或 C FFI。项目交付可复用库、按行接口、PNM/PAM 文件工具、测试和独立互操作证据。

**3、项目方向与通用性**：属于标准编解码基础库及成熟开源项目跨平台移植。统一图像模型、错误与资源预算接口，可由浏览器 Wasm、JS 工具及原生 MoonBit 程序复用，文件和采集 I/O 由宿主适配，不绑定一种设备或业务表结构。已有 DCT JPEG、JPEG XL、JPEG 2000 属于不同编码标准，DICOM 文档解析也不能直接替代 JPEG-LS 像素编解码；本项目不重做通用图像格式集合或 DICOM 文档系统。迁移价值是减少 MoonBit/Wasm 项目的跨语言构建依赖并保留整数数据语义，不要求成熟 C++ 用户整体迁移。已核查的相近项目职责与检索边界见 docs/DIFFERENTIATION.md，不宣称生态中绝对不存在同类项目。

**4、至少三个完整预期使用场景**：

- 场景一，浏览器离线科研图像工具：研究人员导入其他工具产生的受支持 12/16 位灰度 JPEG-LS；宿主先检查尺寸、位深与预算，在 Wasm 中解码，保留原始整数数组供计算，再由显示层另行生成预览或导出 PGM。无损验收逐样本一致，不能把显示用的 8 位预览当作原始数据；ROI 模式仍解码全部相关扫描，仅减少选区输出的存储，不承诺压缩域随机访问。浏览器界面由使用该库的应用提供。
- 场景二，工业采集按行归档：采集宿主提供稳定的灰度/RGB 像素行，RowEncoder 维持相邻重建行及上下文，将压缩字节交给宿主写入临时文件，成功 finish 后由宿主提交归档。默认 NEAR=0；只有业务允许明确整数误差时才配置 NEAR。下游用 CharLS 独立解码，验收原始样本精确恢复或最大绝对误差不超过 NEAR；采集驱动、文件事务和硬件连接由宿主负责，本项目不把合成图验证写成已完成设备集成。
- 场景三，跨语言原始图像批量转换：工程师将 C++/Python CharLS 生成的 JLS 交给本项目文件工具，完成结构检查和完整解码，输出保留位深的 PGM/PPM/PAM 供分析流程使用；反向将受支持 PNM/PAM 编成 JLS，再交外部 CharLS 核对像素。验收覆盖 8/12/16 位、Alpha、近无损及超宽图像；截断、非法参数和超预算输入失败退出，已有输出不覆盖，失败产生的部分文件清理。inspect 只检查结构，不能替代 decode 的熵数据验证。

**5、拟交付并验收的核心功能（当前主干已有实现）**：①SOI/SOF55/LSE/SOS/EOI 标记与多扫描读写；②基于重建邻域的中值预测、梯度上下文、偏差修正、regular/run 模式及受限 Golomb 编解码；③无损与显式 NEAR 近无损，支持指定交织和 T1/T2/T3/RESET；④DRI/RST 重启、LSE4 大尺寸、受检 SPIFF 及 HP1/2/3 扩展；⑤整图、按行拉取/推送、码流分帧与 ROI 输出；⑥PNM/PAM、位深/字节序/stride 布局适配、误差统计与实测编码预算选择；⑦输入尺寸、字节、元数据和段数预算及失败状态保护；⑧跨后端测试、可运行示例、CI、固定黄金向量与双向独立验证。

**6、项目性质**：移植项目，即“CharLS 范围移植＋MoonBit 工程适配”，不是全部原创算法，也不是 libcharls 的绑定。MoonBit 类型与错误、受限位流、行回调、文件宿主、测试和工程文档属于本次适配工作；算法来源、通用辅助脚本复用及 AI 辅助均在 THIRD_PARTY.md 披露。

**7、参考项目与许可证**：CharLS 2.4.2，来源 [team-charls/charls](https://github.com/team-charls/charls/tree/2.4.2)，固定提交 36dd3307e070d8fbc765c3ba890b7e681046fa39；许可证 [BSD-3-Clause](https://github.com/team-charls/charls/blob/2.4.2/LICENSE.md)。移植 regular/run 上下文、预测与样本重建等选定路径，并适配位流、标记及受支持扩展；保留上游版权和完整许可，本工程同用 BSD-3-Clause。独立验证另使用 imagecodecs 2026.11.11 所附 CharLS 2.4.5，不将参考引擎作为核心运行依赖。

**8、GitHub 仓库及有效提交核查**：[SUNhuixin-2007/MoonJLS](https://github.com/SUNhuixin-2007/MoonJLS)，公开默认分支 main；[提交记录](https://github.com/SUNhuixin-2007/MoonJLS/commits/main/)。已逐条核查前 10 个实质开发/工程提交，每次均有实际变更，无空提交或重复提交树；新补的 SPIFF 位置校验和回调重入修复各自含复现及回归测试，未把同一修改拆分凑数。本次申报书更新不计入上述 10 个门槛；逐条职责、SHA 和核查口径见 docs/COMMIT_AUDIT.md。有效性的最终认定以主办方审核为准。

验收基础与边界：生产核心严格有效 MoonBit 代码 4,118 行，测试、示例、生成文件和依赖另计；当前测试与运行证据见 docs/VALIDATION.md、docs/REMOTE_CI.json。JPEG-LS 首版 MAXVAL 必须等于 2^位深−1；两通道交织、sample＋非默认 RESET 的独立验证限制单列。不承诺 Part 2、完整 DICOM、损坏恢复、官方一致性认证或未测试的真实生产语料。
