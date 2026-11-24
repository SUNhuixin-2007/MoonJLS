# 发布与申报状态

2026-11-24 已完成公开推送与 Mooncakes 发布。

## 账号与仓库

- GitHub：[SUNhuixin-2007/MoonJLS](https://github.com/SUNhuixin-2007/MoonJLS)，公开仓库，默认分支 main。
- Mooncakes：[SHX-ai-nb/moonjls@0.1.0](https://mooncakes.io/docs/SHX-ai-nb/moonjls)。GitHub 改名前为 SHX-ai-nb；Mooncakes 保留旧用户名，两者公开资料对应同一 GitHub 数字 ID 315030266。
- 申请人：孙卉欣；电话及私人邮箱未写入公开工程。Git 作者使用 SUNhuixin-2007 和 GitHub noreply 邮箱。
- 首次公开前已修正 5 次本地提交的旧作者，源码和原始时间戳保留；原始备份只存在忽略的 work 目录。

## 已核验结果

- [GitHub Actions](https://github.com/SUNhuixin-2007/MoonJLS/actions/runs/45375471028) 已通过：格式、全目标严格检查、Wasm/Wasm-GC/JS/native 各 42 项测试、282 组双向互操作、80 组扩展独立解码、10 类真实文件场景及接口一致性。
- CI 使用已验证的编译器及标准库 0.10.17+093cb8f9c，避免 latest 更新造成格式规则漂移。首轮最新版本的格式检查失败已保留在运行记录中，修正固定版本后完整重跑通过。
- Mooncakes publish 返回 200 OK；注册表 manifest 和公开文档 HTTP 200，版本 0.1.0，仓库链接归属于 SUNhuixin-2007。
- 在新目录从公开注册表下载安装 0.1.0，再运行消费方 16 位样本往返测试，通过；不是复用本地工程依赖。
- 机器可读证据：REMOTE_CI.json、RELEASE_VERIFICATION.json；Windows 本地检查另见 LOCAL_VALIDATION.json。

Git 传输在本机多次连接重置后，改用 GitHub 官方 Git Database API 上传并逐对象核对 SHA；完整开发历史和本地/远端提交对应一致。未上传历史备份、缓存或登录凭据。

## 比赛申报边界

公开仓库和包发布不等于已提交比赛报名或通过审核。本轮未自动提交含联系方式的报名表。申报书已填写申请人、真实仓库链接与发布命名空间；用户可按最新官方渠道提交。

CharLS 来源、许可与 AI 辅助见 THIRD_PARTY.md；生态差异材料比较已有公开项目职责，不能保证未公开申报没有相邻内容。Windows 本机原生运行仍未验证；云端 Ubuntu 原生测试已通过，二者分开记录。
