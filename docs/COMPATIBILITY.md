# 兼容性边界

基准为 ITU-T T.87 / ISO/IEC 14495-1 baseline。最终目标是完整基线符合性，当前实现及证据仍有下列缺口，没有通过官方一致性认证。完整目标、标准条款与阶段门槛见 [BASELINE_PLAN.md](BASELINE_PLAN.md)；CharLS 的全部能力不自动构成本工程的能力。本轮修改面向计划版本 0.2.0，发布状态另见 [SUBMISSION_STATUS.md](SUBMISSION_STATUS.md)。

| 功能 | 已实现的范围 | 验证方式 |
| --- | --- | --- |
| 整数样本 | 无符号 2–16 位；1–4 分量；API 统一逐行像素交织 | 本地测试；1/3/4 分量双向外部向量，2 分量 none 为外部解码验证 |
| 无损/近无损 | NEAR=0 精确恢复；0≤NEAR≤min(255, floor(MAXVAL/2)) | 包括 NEAR=127/255 的独立像素与误差上限核对；近无损另比较参考重建值 |
| 交织 | none、line、sample；单分量只允许 none | 1/3/4 分量有 CharLS 互操作；两分量 line/sample 只有本地跨接口测试 |
| preset / MAXVAL | 精度 P 为 2–16；实际 MAXVAL 可为 1…`2^P−1`，样本不超过它；T1/T2/T3/RESET 可显式配置 | 原 CharLS 证据为满范围；新增官方参考合成灰度向量 144 组双向，含非满范围；MAXVAL=1/2 另用规范推导测试，见 [MAXVAL_EVIDENCE.md](MAXVAL_EVIDENCE.md) |
| 标记与扫描 | SOI/SOF55/LSE1/SOS/EOI；多 scan；每分量恰好编码一次 | 结构与熵解码分别检查，完整解码拒绝尾随字节 |
| 大尺寸 | Part 1 的 LSE4，2/3/4 字节尺寸；正 Int 范围内且受像素/样本预算约束 | 65536×1、8/16 位双向外部向量；尚未覆盖全部合法出现次序及延迟高度定义 |
| 重启 | 16 位 DRI；当前同尺寸 Hi=Vi=1 模型下 MCU 与行对应；RST0…RST7 循环并重置预测/上下文 | 独立 CharLS 解码与本地序号破坏测试；尚未实现一般异采样 MCU 及宽 DRI，不做损坏恢复 |
| SPIFF | v2.0、unprofiled JPEG-LS header、EOD；尺寸/分量/分辨率校验 | 独立双向向量、冲突拒绝；目录条目语义保持 opaque |
| HP 扩展 | CharLS HP1/HP2/HP3；全范围 8/16 位 RGB、NEAR=0、line/sample | 双向独立像素验证；这是上游扩展，不属于 T.87 核心 |
| 元数据 | 有预算的 APP/COM，添加/替换/剥除；剥除时保留必要 mrfx | 本地验证编辑前后像素不变、拒绝伪造必要标记 |
| 按行 API | encode_rows、decode_rows、RowEncoder；压缩码流 framer | 与整图字节一致、回调拥有权、逐字节分块、失败状态测试 |
| 原始交换 | P2/P3/P5/P6，PAM P7 1–4 分量；8/16 位存储，精度保留 | 分隔符、注释、CRLF、大端、Alpha、65536 宽灰度 8/16 位文件往返验证 |
| 宿主布局 | planar/interleaved，U8/U16BE/U16LE，行/平面 stride | 边界、重叠、无符号值与往返测试 |
| ROI/统计 | 全扫描但只保留选定矩形；直方图、误差、实测 NEAR 预算选择 | 区域/通道顺序、统计原子性与候选预算测试 |

## 当前缺口与证据适用范围

- 属于最终基线目标、当前尚未实现的项目：mapping tables 及续表、table-only/abbreviated 格式、point transform、异采样分量、超过当前 1–4 分量同尺寸模型的规范分量表达、DNL、24/32 位 DRI、完整 LSE4 合法次序及零高度延迟定义。这些是后续交付缺口，不归入 Part 2 或永久排除。
- Part 2、浮点/有符号像素、受损码流修复及完整 DICOM 文档不属于本项目的基线目标。SPIFF 和 HP 扩展分别列示，不能代替基线验收。
- v0.1.x 为建立互操作基础而拒绝非满范围 MAXVAL；该工程守卫已在本轮解除。P=10、MAXVAL=1000 的无损与 NEAR=3 输入、JLS 输出和双向重建文件见 [MAXVAL_EVIDENCE.md](MAXVAL_EVIDENCE.md)。编码保留实际 1000，不静默改成 1023。新增证据以灰度合成图为范围，不能据此宣称所有基线组合已通过。
- 原 imagecodecs/CharLS 的 282 组双向与 80 组扩展用例仍是满范围证据，不能证明任意 MAXVAL。新增官方参考程序的 144 组双向验证另列；旧参考程序不接受 MAXVAL=1/2，且低 MAXVAL 近无损的隐式阈值与最终规范默认值不同，相应用例显式设置合法阈值/RESET，不将它们当成规范默认值的外部证明。
- CharLS 2.4.5 不支持两分量交织扫描，imagecodecs 编码包装也不接受两通道图像形状。两分量 none 有外部解码证据，line/sample 只列本地验证；文件工具对两分量默认使用 none。上游限制可对照 [2.4.5 reader](https://github.com/team-charls/charls/blob/2.4.5/src/jpeg_stream_reader.cpp) 的 `check_parameter_coherent`。
- sample 交织与非默认 RESET 的组合仅有本地重建/推送一致性测试。CharLS 2.4.5 的外部解码未通过该组合；其 factory 在 RESET 非默认时进入标量 traits 分支，与 sample 默认路径不同（见 [factory](https://github.com/team-charls/charls/blob/2.4.5/src/jpegls.cpp)）。这是该参考工具的证据边界，不能据此永久排除标准组合；新增灰度 MAXVAL 证据也不覆盖这个组合。
- 外部编码包装会选择具体交织：RGB 默认 sample、RGBA 默认 line、planar=True 为 none。MoonJLS 的全部指定编码模式另由外部解码验证，不能据此声称外部编码覆盖每一个指定模式。
- ROI 没有 JPEG-LS 压缩域随机访问能力；它必须读取并解码全部相关扫描。Framer 在完整压缩图到达后才做结构检查，不是在线增量熵解码器。

最终验收需要官方 Annex E 全部 12 组，以及其未充分覆盖的参数、映射、Pt、缩略格式、重启和标记语法矩阵。当前 CharLS 用例和新增非满范围用例均不等同于这项验收；尤其不能跳过 Annex E 第 7/8 组异采样测试后宣称完整通过。标准依据为 [ITU 官方 T.87](https://www.itu.int/rec/T-REC-T.87-199806-I/en)。

## 内存与失败语义

整图 API 物化全部样本。`encode_rows`/`decode_rows` 预测状态为两个重建行及固定上下文；前者保留压缩输出、后者保留压缩输入。`RowEncoder` 按行推送并排出完整熵字节，保留两行与不满字节的状态；它不支持多分量 none，因为这种扫描需要回访输入行。

默认 Limits：16,777,216 像素、67,108,864 样本、268,435,456 压缩字节、1,048,576 元数据字节、4,096 段。段数包括 EOI 与扫描内的 RST，SOI 不计入；各编码入口在开始回调或写出前检查所需段数，HP 的 mrfx 同样计入元数据预算。PNM 的元数据预算包含 MAXVAL 后的完整分隔符（LF 或 CRLF）。

调用者可以配置 Limits，但所有尺寸仍必须满足受检 Int 索引范围；行字节计算先用 Int64 再缩回 Int。`PnmSource::open(start~)` 的字节预算作用于 start 到文件尾的该幅图像，不将外部容器前缀计入。若 inspect 使用了扩大的预算，将相同预算传入 `Info::to_json(limits~)`，SPIFF 信息导出不会退回默认像素限制。

回调可能已经写出部分结果后才失败。库以错误通知；RowEncoder/Framer 失败后拒绝复用。Node 文件工具仅用 wx 独占创建输出，失败时删除本次新建文件；已有文件不会被覆盖。二进制 P5/P6 输入按行读取，PAM/ASCII 输入与文件解码会物化整图，报告中有 `full_pixel_array` 字段。

JS、Wasm、Wasm-GC 的结果以本地记录为准；Windows 原生运行缺少 MSVC C++ 工具链和 SDK，未验证。GitHub Ubuntu 的 native 与其他三个后端已通过；远程 CI 与注册表发布状态单列于 `SUBMISSION_STATUS.md`，不与本机 Windows 测试混记。

后续边界修复：SPIFF 包装及其 EOD 必须位于第一幅扫描的熵数据前；RowEncoder 输出回调不可递归调用同一实例的 push/finish，重入在修改状态前拒绝。两者各有独立回归测试，普通扫描后的 APP/COM 注释仍可保留。
