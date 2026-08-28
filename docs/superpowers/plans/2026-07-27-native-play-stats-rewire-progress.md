# 播放统计修复 — 进度报告(2026-07-27 会话结束时)

计划文档:`docs/superpowers/plans/2026-07-27-native-play-stats-rewire.md`
工作分支:`fix/play-stats-rewire`,**专用 worktree `F:\fly_play_stats_rewire`**(注意:主目录 F:\fly_play_recovered 被另一会话的 poster-browse 工作占用,曾发生分支互踩,故本工作全部迁入独立 worktree,继续时请在 worktree 里做)。

## 已完成(全部已提交,均过规格审查)

| 提交 | 内容 | 审查状态 |
|---|---|---|
| `80ff7bd` | NativePlayStatsRecorder 记录器 + 9 用例 | 规格✅ 质量✅ |
| `0a69b25` | 评审意见修复:fakeAsync 看门狗真实计时路径 + 边界加固(共 17 用例) | 复审✅ |
| `97ad730` | fake_async 显式 dev 依赖 | ✅ |
| `914329f` | NativePlayerBridge 四处挂点(launch/resolvePlayback/reloadServerSession/recordProgress) | 规格✅ 质量✅(零必修) |
| `ef5e0cd` | Kotlin 暂停心跳帧(isPaused+pausedHeartbeat)+ 飞牛/服务器族回写守卫 + progress 防御性拷贝 | 规格✅(四态推演全对);**质量审查会话结束时仍在进行,结果未回** |

验证记录:`flutter analyze` 无问题;`flutter test` 488 全绿;Kotlin `:app:compileLiteDebugKotlin` BUILD SUCCESSFUL。

## 待办(按顺序)

1. **补看任务 C 质量审查结论**(若无记录,可重新对 `914329f..ef5e0cd` 做一次质量审查;重点:心跳帧下游消费面、lastRecordedTs 语义、暂停+PiP 组合)。
2. **最终整体评审**:`aebbf3d..ef5e0cd` 全量 diff。
3. **合并**:fix/play-stats-rewire → main(注意 main 已被 poster-browse 会话推进到 1a69f64+,合并前先 rebase 或直接 merge,冲突概率低——四个统计文件与 poster-browse 无交集)。合并后可删 worktree `F:\fly_play_stats_rewire`。
4. **实机验收**(计划 Task 5,6 项清单,必须装真机):
   - 播 ≥1 分钟 → 设置→全局播放数据统计出现数据(观看时长 ≥40s);
   - 壳内切集 → 两条历史,第二条来源「手动切换」;
   - 暂停 2 分钟再继续 → 同一条历史不拆分(靠心跳帧);
   - 退出播放器 40s → 会话收口(finishReason=idle_timeout);
   - 20% 时长门槛 → 观看次数 +1/不计;
   - 飞牛续播位回写不受影响;Emby 同验。
5. **遗留 Minor(不阻塞,择机)**:
   - 切会话后 `_samplesSinceFlush` 重置无直接断言(代码正确);
   - 壳重启时旧壳残余最后一帧可能产生一条 watchedMs≈0 的噪声历史(概率低,实机观察到再修);
   - 元数据国家/年份/题材靠 PlayStatsMetadataBackfillService 回填(飞牛 only),Emby 条目报表维度不全属已知限制。

## 已知限制(设计如此,验收别当 bug)

seek/OP-ED 统计无数据源;autoNext 记为 manualSwitch;后台纯听不计时长;关闭原生渲染器走 Flutter 播放器的路径不在本次范围;externalLocalSource 明确排除。
