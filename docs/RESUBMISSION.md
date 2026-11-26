# MoonJLS 初审补充说明（可粘贴报名表）

针对本轮“尚未承诺完整基线标准符合性，需解释首版 MAXVAL 限制并补充非满范围案例”的意见，已修改项目目标、技术路线和验收材料：

1. **明确最终目标**：实现 ITU-T T.87 / ISO/IEC 14495-1 完整 JPEG-LS 基线标准符合性，以标准第 8 章、Annex E 全部 12 组及专项机制测试共同验收。当前实现进度与最终目标分别列出，不以自身往返或局部互操作替代全部符合性。
2. **解释并解除阶段限制**：v0.1.x 的 MAXVAL=2^P−1 只是首版建立互操作证据的工程限制，不是标准约束或最终支持边界。v0.2.0 已支持 P=2…16、1≤MAXVAL<2^P 及合法 NEAR；按实际 MAXVAL 计算 RANGE/bpp/qbpp/LIMIT、阈值与样本重建，保留真实 MAXVAL，不缩放或改写为满范围。
3. **补充真实双向案例**：MAXVAL=1000、17×9 灰度、NEAR=0/3 的原始 PGM、官方参考编码的 JLS、本库编码的 JLS 和官方解码重建 PGM 均已提交，附 SHA-256。无损案例全部 153 个样本精确相同，近无损案例实测最大绝对误差为 3；独立参考的重建数组也逐样本比较。官方参考分层矩阵共 144 组输入方向与 144 组输出方向通过，不把自身往返计作独立证据。
4. **补齐最终范围与路线**：映射表/续表、table-only/abbreviated、point transform、异采样分量、DNL、宽 DRI/DNL 及合法标记次序均纳入最终基线交付。通过分量 Plane/扫描分组、表状态与字节输出模型、编码域/变换域分离、按 MCU 重启和受检宽字段解析依次实现；当前缺口保留为未完成状态，逐项验收后更新。

项目仓库：[https://github.com/SUNhuixin-2007/MoonJLS](https://github.com/SUNhuixin-2007/MoonJLS)

完整八项申报书：[PROPOSAL.md](https://github.com/SUNhuixin-2007/MoonJLS/blob/main/PROPOSAL.md)

最终支持范围及验收路线：[BASELINE_PLAN.md](https://github.com/SUNhuixin-2007/MoonJLS/blob/main/docs/BASELINE_PLAN.md)

非满范围输入输出与复现：[MAXVAL_EVIDENCE.md](https://github.com/SUNhuixin-2007/MoonJLS/blob/main/docs/MAXVAL_EVIDENCE.md)

实际案例文件：[fixtures/t87-maxval/examples](https://github.com/SUNhuixin-2007/MoonJLS/tree/main/fixtures/t87-maxval/examples)

公开前十次实质提交核查：[COMMIT_AUDIT.md](https://github.com/SUNhuixin-2007/MoonJLS/blob/main/docs/COMMIT_AUDIT.md)

以上是补交材料与已执行证据，不表示主办方已复审通过。邮件所示 2026 年 11 月 30 日为报名补充材料时点，未将其解读为全部标准功能的最终开发验收截止日期。
