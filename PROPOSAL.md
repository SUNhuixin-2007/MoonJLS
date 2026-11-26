# MoonJLS 项目申报书

申请人：孙卉欣；GitHub：SUNhuixin-2007；Mooncakes：SHX-ai-nb（GitHub 改名前的注册名，属于同一账号）。

**1、项目名称**：MoonJLS——面向 MoonBit/Wasm 的 JPEG-LS 无损与近无损图像编解码库。

**2、项目简介与最终目标**：面向科研和工业整数图像，将成熟 CharLS 算法移植为纯 MoonBit 库，最终实现 **ITU-T T.87 / ISO/IEC 14495-1 完整 JPEG-LS 基线标准符合性**，以第 8 章、Annex E 全 12 组及标准机制专项测试验收。当前不声称已经全部符合。v0.1.x 的 `MAXVAL=2^P−1` 只是首版互操作阶段的工程限制，不是标准要求或最终边界；v0.2.0 已解除，按实际 MAXVAL 推导 RANGE/bpp/qbpp/LIMIT、阈值和重建范围，支持 `P=2…16、1≤MAXVAL<2^P、0≤NEAR≤min(255,⌊MAXVAL/2⌋)`。官方参考双向验证共 144 组（90 组非满范围、54 组满范围对照），MAXVAL=1000 的 NEAR=0/3 输入 PGM、参考/本库输出 JLS、独立重建 PGM 及摘要见 [输入输出证据](docs/MAXVAL_EVIDENCE.md)。核心不依赖 C++/Python/FFI。

**3、项目方向与通用性**：属于标准编解码基础库及成熟开源项目跨平台移植。统一图像模型、错误与资源预算接口，可由浏览器 Wasm、JS 工具及原生 MoonBit 程序复用，文件和采集 I/O 由宿主适配，不绑定一种设备或业务表结构。已有 DCT JPEG、JPEG XL、JPEG 2000 属于不同编码标准，DICOM 文档解析也不能直接替代 JPEG-LS 像素编解码；本项目不重做通用图像格式集合或 DICOM 文档系统。迁移价值是减少 MoonBit/Wasm 项目的跨语言构建依赖并保留整数数据语义，不要求成熟 C++ 用户整体迁移。已核查的相近项目职责与检索边界见 docs/DIFFERENTIATION.md，不宣称生态中绝对不存在同类项目。

**4、至少三个完整预期使用场景**：

- 场景一，浏览器离线科研图像工具：研究人员导入其他工具产生的受支持 12/16 位灰度 JPEG-LS；宿主先检查尺寸、位深与预算，在 Wasm 中解码，保留原始整数数组供计算，再由显示层另行生成预览或导出 PGM。无损验收逐样本一致，不能把显示用的 8 位预览当作原始数据；ROI 模式仍解码全部相关扫描，仅减少选区输出的存储，不承诺压缩域随机访问。浏览器界面由使用该库的应用提供。
- 场景二，工业采集按行归档：采集宿主提供稳定的灰度/RGB 像素行，RowEncoder 维持相邻重建行及上下文，将压缩字节交给宿主写入临时文件，成功 finish 后由宿主提交归档。默认 NEAR=0；只有业务允许明确整数误差时才配置 NEAR。下游用 CharLS 独立解码，验收原始样本精确恢复或最大绝对误差不超过 NEAR；采集驱动、文件事务和硬件连接由宿主负责，本项目不把合成图验证写成已完成设备集成。
- 场景三，跨语言原始图像批量转换：工程师将 C++/Python CharLS 生成的 JLS 交给本项目文件工具，完成结构检查和完整解码，输出保留位深的 PGM/PPM/PAM 供分析流程使用；反向将受支持 PNM/PAM 编成 JLS，再交外部 CharLS 核对像素。验收覆盖 8/12/16 位、Alpha、近无损及超宽图像；截断、非法参数和超预算输入失败退出，已有输出不覆盖，失败产生的部分文件清理。inspect 只检查结构，不能替代 decode 的熵数据验证。

**5、核心功能、技术路线与阶段验收**：已实现预测/梯度上下文/偏差修正、regular/run 与受限 Golomb、实际 MAXVAL/NEAR、自定义阈值、同尺寸分量多扫描与交织、16 位 DRI/RST、LSE4、按行接口、PNM/PAM、资源预算、错误保护和独立互操作。**最终基线范围还包含当前未实现的映射表/续表、table-only 与 abbreviated 格式、point transform、异采样分量、DNL、24/32 位 DRI/DNL 及合法标记次序**，不将它们归为 Part 2 排除。拟在现有 Image 外增加含尺寸/Hi/Vi 的分量 Plane 与扫描分组；映射表单独保存 Wt 字节结果并管理安装状态，Pt 分开核查编码域和输出域；重启按 MCU 计数，扩展无符号字段解析后再检查部署预算。依次验收数值域、基线结构、全部符合性矩阵；NEAR 不只核对误差界，还比较独立参考重建值。完整支持范围、缺口和逐项验收见 [BASELINE_PLAN.md](docs/BASELINE_PLAN.md)。SPIFF/HP 扩展单列，不替代基线验收；应用界面和设备驱动由宿主提供。

**6、项目性质**：移植项目，即“CharLS 算法移植＋MoonBit 工程适配及基线能力补齐”。移植已完成部分与最终标准目标分别记录；MoonBit 类型与错误、受限位流、行回调、文件宿主、测试和工程文档属于本次适配工作。算法来源、通用脚本复用及 AI 辅助均在 THIRD_PARTY.md 披露。

**7、参考项目与许可证**：CharLS 2.4.2，来源 [team-charls/charls](https://github.com/team-charls/charls/tree/2.4.2)，固定提交 36dd3307e070d8fbc765c3ba890b7e681046fa39；许可证 [BSD-3-Clause](https://github.com/team-charls/charls/blob/2.4.2/LICENSE.md)，本工程保留原版权并同用 BSD-3-Clause。移植 regular/run、预测与重建路径并适配位流、标记和扩展。开发验证使用 imagecodecs 2026.11.11/CharLS 2.4.5，以及 [ITU T.87 官方附件](https://www.itu.int/rec/T-REC-T.87-199806-I/en) 参考程序；后者限符合性测试，原始软件和图集不并入 BSD 分发。旧参考的适用限制另列，不用它的限制缩减最终标准目标。

**8、GitHub 仓库及有效提交核查**：[SUNhuixin-2007/MoonJLS](https://github.com/SUNhuixin-2007/MoonJLS)，公开默认分支 main；[提交记录](https://github.com/SUNhuixin-2007/MoonJLS/commits/main/)。已逐条核查前 10 个实质开发/工程提交，每次均有实际变更，无空提交或重复提交树；新补的 SPIFF 位置校验和回调重入修复各自含复现及回归测试，未把同一修改拆分凑数。本次申报书更新不计入上述 10 个门槛；逐条职责、SHA 和核查口径见 docs/COMMIT_AUDIT.md。有效性的最终认定以主办方审核为准。

验收基础与边界：生产核心严格有效 MoonBit 代码 4,115 行，测试、示例、生成文件和依赖另计；当前测试证据见 docs/VALIDATION.md，远程 CI 与发布状态另列。满范围限制仅属于 v0.1.x；当前两通道交织、sample＋非默认 RESET 的独立验证限制及未实现的基线项如实列明。完整基线符合性是最终交付目标，当前未宣称完成；Part 2、完整 DICOM、损坏恢复和官方机构认证不属于交付范围。
