# 发布与申报状态

2026-11-26 已完成 0.2.0 公开推送、云端验证与 Mooncakes 发布；已针对初审退回意见补充材料，尚未代表比赛复审通过。

## 账号与仓库

- GitHub：[SUNhuixin-2007/MoonJLS](https://github.com/SUNhuixin-2007/MoonJLS)，公开仓库，默认分支 main。
- Mooncakes：[SHX-ai-nb/moonjls@0.2.0](https://mooncakes.io/docs/SHX-ai-nb/moonjls)。GitHub 改名前为 SHX-ai-nb；Mooncakes 保留旧用户名，两者公开资料对应同一 GitHub 数字 ID 315030266。
- 申请人：孙卉欣；电话及私人邮箱未写入公开工程。Git 作者使用 SUNhuixin-2007 和 GitHub noreply 邮箱。
- 首次公开前已修正 5 次本地提交的旧作者，源码和原始时间戳保留；原始备份只存在忽略的 work 目录。

## 已核验结果

- [GitHub Actions](https://github.com/SUNhuixin-2007/MoonJLS/actions/runs/45801454784) 已通过：格式、全目标严格检查、Wasm/Wasm-GC/JS/native 各 50 项测试、CharLS 282 组双向及 80 组扩展、官方参考固定输入 144 组、14 类真实文件场景及接口一致性。
- CI 使用已验证的编译器及标准库 0.10.17+093cb8f9c，避免 latest 更新造成格式规则漂移。首轮最新版本的格式检查失败已保留在运行记录中，修正固定版本后完整重跑通过。
- Mooncakes publish 返回 200 OK；注册表 manifest 包含 0.2.0，公开文档 HTTP 200，仓库链接归属于 SUNhuixin-2007。
- 更新注册表索引后，从公开注册表下载安装 0.2.0，实际依赖 manifest 为 0.2.0；16 位整数、MAXVAL=1000 无损及近无损三个消费方测试全部通过，没有使用本地工程依赖。
- Windows 官方参考现场测试为 144 组双向，其中 90 组非满范围、54 组满范围对照；Linux CI 只运行固定参考输入，未声称现场输出方向。详细见 MAXVAL_EVIDENCE.md。
- 官方附件全部 12 个 JLS 文件已检查解码侧：10 个通过、2 个异采样缺口，汇总 PARTIAL；编码器符合性未执行，非默认图像来源存在文档差异，见 ANNEX_E_STATUS.md。
- 机器可读证据：REMOTE_CI.json、RELEASE_VERIFICATION.json；Windows 本地检查另见 LOCAL_VALIDATION.json。

Git 传输在本机多次连接重置后，改用 GitHub 官方 Git Database API 上传并逐对象核对 SHA；完整开发历史和本地/远端提交对应一致。未上传历史备份、缓存或登录凭据。

## 比赛申报边界

完整基线符合性已明确列为最终项目目标；v0.1.x 的满范围 MAXVAL 限制为历史阶段边界，0.2.0 已解除。尚未实现的映射/Pt/异采样/DNL/宽 DRI 等逐项保留在 BASELINE_PLAN.md，不将它们从最终目标中删去。

公开仓库和包发布不等于已提交比赛报名或通过审核。本轮未自动提交含联系方式的报名表或发送邮件。完整八项申报书为 PROPOSAL.md；可粘贴的本轮补充说明为 RESUBMISSION.md。按用户收到的邮件，可于 2026-11-30 前更新报名表交复审；该日期不被解释成全部标准实现的最终开发验收截止日。

CharLS 来源、许可与 AI 辅助见 THIRD_PARTY.md；生态差异材料比较已有公开项目职责，不能保证未公开申报没有相邻内容。Windows 本机原生运行仍未验证；云端 Ubuntu 原生测试已通过，二者分开记录。

申报书保留八项要求；公开前十次提交均有非空、非重复且已列明的工程贡献，详见 COMMIT_AUDIT.md。本轮 MAXVAL 能力和独立证据合为一项实质功能提交；发布后的验证记录单列，不靠拆分、空提交或文档更新满足前十次门槛。0.1.0/0.1.1 保留为历史发布版本。

八项申报书与逐条提交证据已公开；最低数量核查固定审阅前十次实质变更，不将申报书及本次发布记录更新计入该十次门槛。
