<div align="center">

<img src="docs/images/logo.png" width="128" height="128" alt="Next TODO">

# Next TODO · 接下来

**Mac 上一份小而安静的待办清单。记下来，看清接下来做什么，然后继续你的一天。**

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20WidgetKit-F05138?logo=swift&logoColor=white)
![Version](https://img.shields.io/badge/version-1.0-orange)
![Privacy](https://img.shields.io/badge/数据-只留在你的%20Mac-2ea44f)

[English](README.md) · 简体中文

</div>

---

## 亮点

- **记得快。** 输入任务，按回车。粘贴一整段大纲，会变成带子任务的清单，最多三层。
- **菜单栏快速添加。** 随时随地加一条，输入框下面是最值得看的三件事。
- **两块桌面小组件。** 「还剩多少」统计逾期、今天、以后和未排期的数量。「接下来」按日期列出即将到来的任务，直接在桌面上点圆圈就能完成。
- **为 Mac 而做。** 自定义快捷键，撤销和重做，文字大小小、中、大三档，浅色和深色外观，支持 VoiceOver 和完整的键盘操作。
- **隐私优先。** 不用注册，不用登录，没有广告，没有统计，也不联网。任务不会离开你的 Mac。
- **多语言。** English、English (Australia)、Français、日本語、简体中文、繁體中文，默认跟随系统语言。

## 安装

Next TODO 即将登陆 Mac App Store。需要 macOS 15 或更高版本。

## 上手

1. 打开 Next TODO，输入第一条任务。
2. 点菜单栏图标，在任何应用里都能添加任务。
3. 添加小组件：点菜单栏的日期，选 **编辑小组件**，搜索 *Next TODO*，选中号或大号。

| 操作 | 效果 |
| --- | --- |
| 点任务 | 添加子任务 |
| 右键任务 | 改标题、设置截止时间或删除 |
| 粘贴多行文字 | 生成带子任务的大纲 |
| 拖动任务 | 调整顺序 |
| 点小组件里的圆圈 | 不打开应用直接完成 |

有子任务的条目，要等子任务全部完成才算完成。小组件只统计没有子任务的叶子任务，所以数字和你真正要做的事一致。

## 设置

语言、文字大小、快捷键、小组件徽章，以及清空今天或全部任务。改动会立即保存。

## 隐私

任务和偏好保存在你 Mac 上的 App Group 容器里，由应用和小组件共用。每次写入前都会备份，文件损坏时不会被悄悄覆盖。详见[隐私政策](docs/PRIVACY.md)。

## 从源码构建

需要 Xcode 26 和 macOS 15 或更高版本。

```bash
git clone https://github.com/Trade-Offf/NextUp.git
cd NextUp
open NextUp.xcodeproj
```

运行 **NextUp** scheme。跑测试：

```bash
xcodebuild -project NextUp.xcodeproj -scheme NextUp \
  -destination 'platform=macOS' -derivedDataPath build test
```

Bundle ID、App Group、URL Scheme 和版本号都在 [`Config/NextUp.xcconfig`](Config/NextUp.xcconfig)。

## 目录

| 目录 | 内容 |
| --- | --- |
| `NextUpApp` | 主窗口、菜单栏和设置 |
| `NextUpWidget` | 桌面小组件 |
| `NextUpShared` | 两边共用的任务、排序、存储和多语言文案 |
| `NextUpTests` | 单元测试 |
| `docs` | [验收记录](docs/ACCEPTANCE.md)、[上架文案](docs/APP_STORE.md)、[隐私政策](docs/PRIVACY.md) |

---

<div align="center">

© 2026 佳林 李，保留所有权利。

</div>
