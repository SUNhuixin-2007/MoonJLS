# 验证方法与证据

## 复现入口

```sh
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon fmt --check
moon info
moon run cmd/demo --target js
python scripts/count_loc.py --minimum 4000
python -m pip install --target work/pydeps -r scripts/requirements-dev.txt
python scripts/interop.py
```

2026-11-24 的完整执行记录为 [LOCAL_VALIDATION.json](LOCAL_VALIDATION.json)，结果 `PASS_WITH_LIMITATIONS`：

| 检查 | 实测结果 |
| --- | --- |
| 编译/格式 | `moon check --target all --deny-warn`、`moon fmt --check`、`moon info` 通过 |
| Wasm / Wasm-GC / JS | 每个目标 42 项测试全部通过（同一套测试在三个后端执行，不写成 126 个独立用例） |
| 独立双向 | 282 组图像；CharLS → MoonJLS 与 MoonJLS → CharLS，逐样本核对 |
| 扩展独立解码 | 80 组；重启、推送编码、自定义阈值与 RESET；只计有对应外部解码证据的组合 |
| 真实文件 | 10 类场景，含中文路径、8/12/16 位、Alpha、近无损、拒绝覆盖与失败输出清理 |
| 生产规模 | 5,771 物理行；5,153 非空非注释行；4,100 严格有效核心行 |
| Windows native | NOT_RUN：缺少 MSVC C++ 编译/链接工具和 SDK |
| 远程 CI | 尚未推送，未在托管服务执行 |

工具链为 moon 0.1.20261021、moonc v0.10.17，Node v24.22.3。测试、命令行工具、黄金向量、生成接口与依赖均不计入核心规模。逐文件统计和各命令退出码保存在 JSON 中。

## 独立 oracle

固定 `imagecodecs==2026.11.11`，运行时报告的引擎为 `charls 2.4.5`。算法移植依据另为 CharLS 2.4.2，来源版本与验证版本分别披露。Python 和 NumPy 只构造公开整数样本与比较数组，不重写一份 JPEG-LS 参考解析器。

1. 构造阶跃/平坦游程、渐变、确定性噪声、零/最大值边界与超宽图像，保留所有输入样本。
2. 独立 CharLS 编码，保存 `.jls` 字节和独立解码的重建值。
3. MoonJLS 解码外部码流，比较 frame 与全部重建样本。
4. MoonJLS 对同组输入编码，再由 CharLS 解码；与 MoonJLS 解码的样本数组比较。
5. NEAR=0 要求完全恢复；NEAR>0 核查两种编码器的最大绝对误差都不超过 NEAR。

不要求两个合法编码器输出完全相同的压缩字节。向量覆盖不同精度、零/最大值、行尾 run、上下文残差符号与三种交织；外部编码器接口可直接产生的组合与仅用外部解码验证的组合单列。

## 黄金样本维护

脚本生成确定性、带 SHA-256 的样本清单，完整字节保存在 `fixtures/`。默认运行将固定版本重新编码的字节、SHA-256、重建样本与已提交黄金清单核对，再做交叉验证；它不会写回黄金清单；更新样本必须显式指定 `--generate-fixtures`，审查变更后再提交，不能通过重写预期值掩盖回归。

样本均为合成值，无真实医学图像或授权不明的数据。它们可以证明覆盖的算法路径兼容，不能代替真实系统集成、全部 JPEG-LS 生产图像语料或官方认证。

## 本地与远程结果区分

CI workflow 文件是复现入口，当前没有远程仓库，因此没有“云端 CI 已通过”的结论。Windows 原生测试若受 C++ 编译器或 SDK 缺失影响，应明确列为未运行或未通过，不能与 Wasm/JS 的结果合并。

## 单独列出的组合限制

- 两通道 none 有外部解码验证；line/sample 只有本地编码、解码与推送一致性测试，不能算入外部通过矩阵。
- 自定义 T1/T2/T3 在 none/line/sample 均有独立解码向量；自定义 RESET 的外部证据限 none/line，sample 的外部测试使用 RESET=64。sample+RESET=13 的本地重建与推送一致性测试单列，不声称通过 CharLS。
- 非满范围 MAXVAL 显式拒绝。探索性 MAXVAL=1000 外部解码没有得到一致像素，该结果没有纳入通过数量。
- 重启输出由 CharLS 独立解码；所用 Python 包装不提供相应编码参数，不能将它写成外部编码方向也覆盖了重启。HP 与 SPIFF 则有双向向量。
- 语料为公开合成数据，没有正式一致性认证、真实医学工作流或生产图像全集的结论。

## 文件消费者复现

```sh
python scripts/test_file_cli.py
node scripts/moonjls.mjs inspect fixtures/gray8.jls
node scripts/moonjls.mjs decode fixtures/gray8.jls work/gray8.pgm
```

第三条命令的目标文件必须尚不存在。Node 仅管理精确范围读写和输出文件；JPEG-LS、PNM/PAM 解析、样本重建与图像数据转换都在 MoonBit 实现。inspect 明确返回 `entropy_validated=false`，避免将结构扫描当作完整解码。

## 本地检查补充

本轮新增 11 项测试，从 31 项增至 42 项。`hardening_wbtest.mbt` 覆盖放宽 Limits 后的 32 位行字节溢出、编码前段数预算、RST 计数、HP 必需标记预算、PNM 头部分隔符预算、超宽文件重开、原始输入字节预算和自定义 Limits 的 SPIFF JSON 导出。

还测试了恰好达到预算时能够正常编码/解码，并对普通灰度、sample 交织、带重启的 planar 扫描、SPIFF+HP 四种种子执行所有单字节位置的逐位翻转。变异可能得到另一幅合法图像；测试要求结果要么为受预算约束的合法样本，要么为 JlsError，不能崩溃或无界分配。这不是校验和或损坏恢复保证。

验证脚本记录核心、测试、配置、脚本、fixtures 的内容指纹，检查运行前后未改变。日志开始先写 RUNNING，外部命令缺失会记录失败，避免旧通过记录被误当作本次结果。源码包没有 .git 目录也可生成同一内容指纹；已用独立临时副本验证这一点。
