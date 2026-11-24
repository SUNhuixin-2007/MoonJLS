# GitHub 有效提交核查

核查 main 的前 10 个提交；本次申报书/核查表提交不计入门槛。十次均有实际变更，未见空提交或重复提交树。非空只是必要检查，实质贡献逐项列出，不把行数或 SHA 数量作为主办方最终认定。

| 提交 | 实际贡献 | 修改文件数 |
| --- | --- | --- |
| [9b4d188b](https://github.com/SUNhuixin-2007/MoonJLS/commit/9b4d188b8db1116cf193c0ac01517039d40aeca6) | 建立样本模型、预设参数和 JPEG-LS 填充/Golomb 位流基础 | 8 |
| [ecd5016c](https://github.com/SUNhuixin-2007/MoonJLS/commit/ecd5016c06d3e605499f37f5856af85c46b4dee1) | 实现真实 regular/run 编解码、扫描、行接口及原始图像适配 | 38 |
| [7a382b10](https://github.com/SUNhuixin-2007/MoonJLS/commit/7a382b1055276c5c04af2dd70c5e9de929ba7992) | 加入固定 CharLS 黄金语料、双向互操作和真实文件验证 | 11 |
| [cfa179f3](https://github.com/SUNhuixin-2007/MoonJLS/commit/cfa179f382b2e5468e93f5bab1060ed96d08ca49) | 补齐移植来源、技术路线、生态差异和兼容性证据 | 8 |
| [c7a735a8](https://github.com/SUNhuixin-2007/MoonJLS/commit/c7a735a864b49629b0f923bcd7ed326818ce41f3) | 修复尺寸溢出、预算漏检、超宽 PNM 和参数贯穿，并补回归 | 20 |
| [beebbecf](https://github.com/SUNhuixin-2007/MoonJLS/commit/beebbecf5225d8580be6b3e88e4b8513bf623f09) | 确认账号改名后正确的发布命名空间、仓库及导入配置 | 15 |
| [7fff375e](https://github.com/SUNhuixin-2007/MoonJLS/commit/7fff375e3f5cb931fc3d5af03ec06d036069e7b8) | 修复已发生的云端格式检查失败，固定验证过的编译器/core | 2 |
| [821d465d](https://github.com/SUNhuixin-2007/MoonJLS/commit/821d465da59e51930b2cb1f278a61873054393cb) | 记录实际通过的云端 CI、注册表发布与新项目安装验证 | 7 |
| [830c598e](https://github.com/SUNhuixin-2007/MoonJLS/commit/830c598e0bb043a5112f26a798b6b1e418af2342) | 修复 SPIFF/EOD 出现在扫描之后仍被接受的问题；带失败复现及正例 | 2 |
| [ae9d7f76](https://github.com/SUNhuixin-2007/MoonJLS/commit/ae9d7f76259fe72239cd961833020490c6451a36) | 拒绝输出回调递归 push/finish 导致的状态重入；带独立回归 | 2 |

最新两项修复分别先运行了可复现失败的测试，再完成实现与回归，各自完整提交；没有把同一功能拆成多次或制作空提交。原有 CI 版本固定提交对应一次真实云端失败及随后的成功运行，发布元数据提交包含真实命名空间与导入调整。

核查命令：git rev-list --count HEAD、git diff-tree --root --numstat -r <sha>、git show -s --format=%T <sha>；具体文件清单与作者日期见 COMMIT_AUDIT.json。后续新增提交可从公开提交页查看；本表固定描述已审查的十次贡献。
