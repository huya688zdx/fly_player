# Danmaku 模块设计说明

## 1. 目标

这个模块的目标不是先把弹弹play API 直接接进来，而是先把播放器里的弹幕架构定型，避免后面越接越乱。

当前设计目标：

- 弹幕层独立于 `mpv` 播放内核
- 弹幕层独立于字幕层
- 弹幕层不抢手势，不影响进度拖动、双击、上下 UI
- 设置、数据源、渲染三层分离
- 后续可以平滑接入弹弹play、本地弹幕文件、手动匹配
- 尽量不把新增状态继续堆进 `mpv_player_page.dart`

这套设计是围绕当前项目的播放器结构做的。当前播放器本身就是：

- 原生视频视图
- Flutter Overlay 控制层
- 多个独立 mixin 管理功能

所以弹幕最合适的接入方式也是独立 overlay。

## 2. 当前已经落下来的雏形

当前代码只完成了“架构雏形”和“预览弹幕”，没有真正接弹弹play网络数据。

已存在文件：

- `lib/danmaku/models/danmaku_comment.dart`
- `lib/danmaku/models/danmaku_settings.dart`
- `lib/danmaku/settings/danmaku_settings_store.dart`
- `lib/danmaku/controller/danmaku_controller.dart`
- `lib/danmaku/render/danmaku_overlay.dart`
- `lib/player/mpv_player_danmaku_mixin.dart`

当前已实现能力：

- 播放器里有独立弹幕 overlay
- 可在播放器设置里打开“弹幕设置”
- 设置支持持久化
- 有预览弹幕可验证样式、层级、避让和性能
- 切集/换源时会同步弹幕上下文

当前未实现：

- 弹弹play API 请求
- 自动匹配
- 弹幕缓存
- 真实时间轴调度
- 重复弹幕合并
- 关键词过滤
- 高级弹幕
- 人像/主体检测

## 3. 为什么这样拆

### 3.1 不把弹幕写进 `feiniu_api.dart`

弹幕不是 NAS 自身数据，属于外部来源。  
如果写进 `feiniu_api.dart`，以后会把 NAS 接口和弹幕源强耦合。

正确做法：

- NAS 继续只处理本地媒体信息
- 弹弹play、新弹幕源放到独立模块

### 3.2 不把弹幕画成很多个 Flutter widget

如果一条弹幕一个 `Positioned + Text`，弹幕密度一高就会抖。

当前雏形已经改成：

- 单个 `CustomPaint`
- 单个 `RepaintBoundary`
- 根据当前时间窗绘制活跃弹幕

后续真实弹幕接入时，也必须继续保持这个方向。

### 3.3 不让弹幕参与触摸

弹幕层必须始终 `IgnorePointer`。  
原因很简单：当前播放器已经有这些高频交互：

- 双击暂停
- 水平拖动 seek
- 长按倍速
- 上下 UI 唤出/隐藏

如果弹幕层也参与命中，后面会不断出现“有时候点不动”“seek 不跟手”的问题。

## 4. 当前模块职责

### 4.1 `danmaku_comment.dart`

职责：

- 描述单条弹幕的基础模型
- 目前只有最小字段：时间、文案、类型、颜色

后续应该补充：

- 用户 ID
- 弹幕来源
- 权重
- 屏蔽标签
- 是否重复弹幕
- 字号级别
- 发送时间

### 4.2 `danmaku_settings.dart`

职责：

- 保存弹幕显示设置
- 作为 UI、调度器、渲染器共享的配置对象

当前已有：

- 总开关
- 预览开关
- 滚动/顶部/底部开关
- 不透明度
- 字体倍率
- 显示区域
- 字幕避让
- 中央区域避让

后续应该补充：

- 速度倍率
- 最大同屏条数
- 重复弹幕合并开关
- 关键词屏蔽
- 彩色弹幕开关
- 仅白色弹幕模式
- 描边粗细
- 行距
- 屏蔽发送者

### 4.3 `danmaku_settings_store.dart`

职责：

- 只负责设置持久化

注意：

- 这个 store 不要去缓存真实弹幕数据
- 真实弹幕缓存要单独做 `DanmakuCacheStore`

### 4.4 `danmaku_controller.dart`

职责：

- 当前是最轻量的控制器
- 管理设置、当前媒体上下文、预览弹幕数据

未来扩展方向：

- 负责调度真实弹幕
- 维护当前活跃弹幕窗口
- 处理暂停/恢复/seek/切集
- 对接缓存层和数据源层

注意：

- 这里不要直接发 HTTP 请求
- 网络请求应该交给独立数据源类

### 4.5 `danmaku_overlay.dart`

职责：

- 真正绘制弹幕
- 当前先做了基础滚动、顶部固定、底部固定三类

后续这个文件应该继续只关注“渲染”，不要塞进网络和业务判断。

可以继续补的方向：

- 文本布局缓存
- 轨道冲突处理
- 最大同屏密度控制
- FPS 限制
- 丢帧时的降级策略
- 更细的字幕区避让

### 4.6 `mpv_player_danmaku_mixin.dart`

职责：

- 作为播放器和弹幕模块之间的桥接层

只应该处理三件事：

- 加载弹幕设置
- 同步当前播放上下文
- 提供弹幕设置页

不要在这里写：

- 弹幕网络请求
- 文本绘制
- 轨道算法

## 5. 当前播放器里的接入位置

### 5.1 Overlay 接入点

当前接在：

- `lib/player/mpv_player_view_mixin.dart`

层级顺序现在是：

1. 视频画面
2. 弹幕层
3. 加载层/手势层/控制 UI

这个顺序的好处：

- 弹幕在视频之上
- 弹幕不会压住操作提示
- 控制 UI 显示时仍然最上层

### 5.2 生命周期接入点

当前接在：

- `lib/player/mpv_player_runtime_mixin.dart`

目前已经在播放器源切换后同步：

- 当前标题
- 当前季/集上下文
- 当前是否属于 TV 类片源

后续要补：

- `pause()` 时冻结弹幕时间推进
- `play()` 时恢复
- `seek` 开始时暂停调度
- `seek` 结束时重建活跃弹幕窗口

## 6. 后续接弹弹play时建议新增的文件

建议继续保持独立目录，不要把请求散落到播放器或详情页里。

建议新增：

- `lib/danmaku/api/dandanplay_api.dart`
- `lib/danmaku/api/dandanplay_models.dart`
- `lib/danmaku/source/danmaku_source.dart`
- `lib/danmaku/source/dandanplay_source.dart`
- `lib/danmaku/cache/danmaku_cache_store.dart`
- `lib/danmaku/match/danmaku_match_context.dart`
- `lib/danmaku/match/danmaku_match_result.dart`
- `lib/danmaku/engine/danmaku_scheduler.dart`
- `lib/danmaku/engine/danmaku_lane_allocator.dart`
- `lib/danmaku/filter/danmaku_filter.dart`

建议职责如下：

### `dandanplay_api.dart`

只负责接口调用和响应解析。

不要做：

- UI 逻辑
- 业务重试策略
- 调度

### `danmaku_source.dart`

建议做成抽象接口，例如：

- `matchEpisode(...)`
- `fetchComments(...)`

后面你想加本地 XML、B 站导出、其他弹幕源，都可以继续复用播放器接入层。

### `dandanplay_source.dart`

负责：

- 根据当前媒体上下文向弹弹play做匹配
- 拉取弹幕列表
- 把返回映射成 `DanmakuComment`

### `danmaku_cache_store.dart`

负责两种缓存：

- 匹配结果缓存
- 弹幕内容缓存

不要把缓存继续塞回 `SharedPreferences`。  
设置是设置，弹幕数据是弹幕数据，这两个量级不同。

## 7. 推荐的数据流

后续真实接入时，建议固定成下面这条链路：

1. 播放器进入或切集
2. `mpv_player_danmaku_mixin.dart` 同步媒体上下文
3. `DanmakuController` 判断当前是否允许自动匹配
4. `DanmakuSource` 先读缓存
5. 缓存没有，再发匹配请求
6. 拿到 episode / media 匹配结果后拉弹幕数据
7. 解析为 `DanmakuComment`
8. 建立时间索引
9. `DanmakuOverlay` 只消费当前时间窗的活跃弹幕

必须坚持一点：

- 弹幕加载失败不能影响视频播放

也就是说，弹幕链路永远是“旁路能力”，不是主链路。

## 8. 推荐的自动匹配策略

对当前项目，建议先只对 TV 做自动匹配。

优先级建议：

### TV

自动匹配条件可优先使用：

- `tvTitle`
- `seasonNumber`
- `episodeNumber`
- `duration`
- 文件名

### Movie

第一阶段不做自动弹幕，或者只做手动选择。

原因：

- 电影弹幕价值不如番剧稳定
- 误匹配成本高

### 第三类 `Video / Directory`

第一阶段默认关闭自动匹配，只留手动入口。

原因：

- 文件命名非常不稳定
- 目录型资源可能本身没有结构化剧集信息

## 9. 性能原则

后续真实开发时必须遵守：

### 9.1 解析不要放 UI isolate

弹幕数据解析、排序、时间索引建立，都建议放 isolate 或至少做异步分批。

### 9.2 渲染只看时间窗

不要每帧扫描整包弹幕。  
应该只维护当前时间附近一小段的活跃集合。

### 9.3 不要每帧 `setState`

弹幕刷新应该尽量走：

- `Listenable`
- `CustomPainter`
- `RepaintBoundary`

不要让整页播放器跟着一起 rebuild。

### 9.4 要有降级策略

后续必须支持这些降级手段：

- 降低最大同屏数
- 降低刷新频率
- 合并重复弹幕
- 只保留滚动弹幕
- 降低文本描边和阴影复杂度

## 10. 关于“人像防遮挡”

这个功能可以做，但第一版不要做实时人像检测。

建议分 3 阶段：

### 第一阶段

只做区域避让：

- 底部字幕区避让
- 中央主体区避让
- 控制 UI 区域避让

当前雏形已经先预留了：

- `avoidSubtitleArea`
- `avoidCenterArea`

### 第二阶段

做静态主体保护区：

- 动漫内容一般主体位于中心偏下
- 可给出默认安全区域

### 第三阶段

才考虑轻量动态检测：

- 低频采样
- 只输出禁用区域
- 不做逐帧精确识别

不要在 Flutter 层做逐帧图像分析，这会直接拖垮性能。

## 11. 推荐的迭代顺序

### 第 1 步

把真实数据源接口补出来：

- `DanmakuSource`
- `DanDanPlaySource`
- `DanDanPlayApi`

### 第 2 步

把预览弹幕切成真实弹幕加载：

- TV 自动匹配
- 拉取弹幕
- 建时间索引

### 第 3 步

补过滤和缓存：

- 关键词过滤
- 重复弹幕压缩
- 本地缓存

### 第 4 步

补高级体验：

- 手动匹配
- 导入本地弹幕
- 主体避让升级
- 更细的样式控制

## 12. 当前明确不要做的事

后面接手的人请不要直接这么做：

- 不要把弹幕请求写进 `feiniu_api.dart`
- 不要把弹幕状态继续堆进 `MpvPlayerPage` 主状态
- 不要一条弹幕一个 widget
- 不要让弹幕层接管触摸事件
- 不要让弹幕请求阻塞视频播放
- 不要第一版就做人脸检测

## 13. 后续接手时建议先检查的文件

如果后面要继续完善，先从这几处看：

- `lib/danmaku/README.md`
- `lib/danmaku/controller/danmaku_controller.dart`
- `lib/danmaku/render/danmaku_overlay.dart`
- `lib/player/mpv_player_danmaku_mixin.dart`
- `lib/player/mpv_player_view_mixin.dart`
- `lib/player/mpv_player_runtime_mixin.dart`

## 14. 当前状态总结

现在这套代码的定位很明确：

- 不是最终版弹幕功能
- 是一个可继续扩展的播放器弹幕骨架
- 已经把后续最关键的架构方向定好了

后面继续补的时候，尽量遵守这个原则：

- 数据源可替换
- 设置可持久化
- 渲染独立
- 调度独立
- 播放器只做桥接

只要不打破这五条，后面无论接弹弹play还是别的弹幕源，都不会失控。
