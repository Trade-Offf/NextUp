# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS native (SwiftUI + WidgetKit, macOS 15+). Not web, iOS or Android; no cross-platform adaptation.

## Users
个人工作者，在 Mac 上快速记下任务，靠桌面小组件随时知道「还剩多少、接下来做什么」。不想用重型项目管理工具。

## Product Purpose
Next TODO（应用内中文名「接下来」）是一个纯本地的待办应用：主窗口、菜单栏快速添加、两个桌面小组件。成功标准是记录几乎零成本，打开桌面一眼看到进度。

## Positioning
纯本地、无账号、无网络、无通知；粘贴一段大纲一次建多条任务；小组件只统计叶子任务，数字不重复计算父任务。

## Operating Context
- 记录：主窗口输入框、菜单栏快速添加、全局快捷键。
- 查看：中号小组件「还剩多少」（逾期/今天/以后/未排期），大号小组件「接下来」（按日期列出）。
- 数据通过 App Group 容器在应用和小组件间共享，仅存本机。

## Capabilities and Constraints
- 最低 macOS 15.0；无登录、无云同步、无通知、无 AI、无私有 API。
- 版本保持 1.0；Mac App Store 上架，商店名 Next TODO，bundle com.binyu.nextupapp。
- 小组件图库只出现两个小组件；角标默认关闭；容器圆角 8pt。
- 截止日期、清空今日/全部等语义按既有规则，不随视觉调整而改。

## Brand Commitments
- 商店名 Next TODO；中文名「接下来」。
- 铝拉丝质感表面（MetalCardBackground）和细分隔线是现有身份，视觉优化保留。

## Evidence on Hand
- 真实使用数据仅在本机；没有用户评价、下载量或第三方背书，不得编造。
- 验收清单见 docs/ACCEPTANCE.md。

## Product Principles
1. 记录要比思考更快：输入、回车、完成。
2. 任务文字是主角，日期和统计是配角。
3. 颜色只表示逾期，其余保持克制。
4. 数据留在本机，不为功能牺牲隐私。
5. 小组件的数字必须经得起核对。

## Accessibility & Inclusion
VoiceOver 可读、全流程键盘可操作、尊重「减弱动态效果」、深浅色文字对比度不低于 4.5:1。
