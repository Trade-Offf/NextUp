# Next TODO

macOS 上的个人待办（中文名「接下来」）。主窗口记事，菜单栏快速添加，桌面放两块小组件。

不登录，不联网，不发系统通知，不上传任何数据。任务只保存在这台 Mac 上，由主应用和小组件共用一个 App Group 容器。

## 能做什么

- 记一条，或一次粘贴多行大纲。层级最多三层。
- 点任务添加子任务。有子任务的条目不能单独勾选，子任务全部完成后它才算完成。
- 右键可以改标题、设置截止时间或删除。拖动调整顺序，支持撤销和重做。
- 菜单栏图标：输入框下面是接下来最值得看的三件事。
- 小组件有两块。中号「还剩多少」显示逾期、今天、以后、未排期的数量；大号「接下来」按日期列出任务，可以直接点圆圈完成。小组件只统计没有子任务的叶子任务。
- 设置里可以选语言、文字大小（小、中、大）、自定义快捷键、清空今日或全部数据，以及是否在小组件显示徽章。

支持语言：English、English (Australia)、Français、日本語、简体中文、繁體中文。默认跟随系统语言，系统语言不在列表里时使用英语。

最低系统是 macOS 15。

## 跑起来

用 Xcode 打开 `NextUp.xcodeproj`，运行 Next TODO。或在工程目录执行：

```bash
xcodebuild -project NextUp.xcodeproj -scheme NextUp -destination 'platform=macOS' -derivedDataPath build test
open "build/Build/Products/Debug/NextUp.app"
```

关闭窗口不会退出应用，在菜单栏里选「退出 Next TODO」才会退出。

添加小组件：点菜单栏的日期或时间，底部选「编辑小组件」，搜索 Next TODO，添加中号或大号。

## 工程

| 目录 | 作用 |
| --- | --- |
| `NextUpApp` | 主窗口、菜单栏和设置 |
| `NextUpWidget` | 桌面小组件 |
| `NextUpShared` | 两边共用的任务、排序、存储和多语言文案 |
| `NextUpTests` | 单元测试 |
| `Config/NextUp.xcconfig` | Bundle ID、App Group、URL Scheme、版本号 |
| `docs/ACCEPTANCE.md` | 验收记录 |
| `PRODUCT.md` | 产品定位和约束 |

标识只改 `Config/NextUp.xcconfig`。Swift 里的占位值和它不一致时，测试会失败。

## 数据

任务和偏好保存在 App Group 容器 `372XT34PQJ.com.binyu.nextupapp` 里，文件有 `todos.json`、`todos.json.bak` 和 `preferences.json`。写入前会备份，文件损坏时界面会提示并支持从备份恢复。
