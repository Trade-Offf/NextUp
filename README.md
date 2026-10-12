# Next Up

macOS 上的个人待办。主窗口记事，菜单栏看接下来三件，通知中心放一块小组件。

不登录，不上传，不加系统通知。任务只写在这台 Mac 上：

`~/Library/Application Support/NextUp/`

## 能做什么

- 记一条，或一次粘贴大纲。层级最多三层。
- 点标题添加子项。有子项的条目不能单独勾完，子项都完成它才算完成。
- 左滑或右键删除。右键可以改标题。
- 菜单栏清单图标：输入框下面是接下来最值得看的三件。
- 通知中心有中号和大号。中号最多 3 条顶层。大号展开未完成的子项，大任务之间有分割线。

界面是简体中文。最低系统是 macOS 15。

## 跑起来

用 Xcode 打开 `NextUp.xcodeproj`，运行 Next Up。或在工程目录执行：

```bash
xcodebuild -project NextUp.xcodeproj -scheme NextUp -destination 'platform=macOS' -derivedDataPath build test
open "build/Build/Products/Debug/NextUp.app"
```

关闭窗口不会退出。菜单栏里的「退出 Next Up」才会退出。

把小组件放进通知中心：点菜单栏的日期或时间，底部选「编辑小组件」，搜索 Next Up，添加中号或大号。

## 工程

| 目录 | 作用 |
| --- | --- |
| `NextUpApp` | 主窗口和菜单栏 |
| `NextUpWidget` | 通知中心小组件 |
| `NextUpShared` | 两边共用的任务、排序和存储 |
| `NextUpTests` | 单元测试 |
| `Config/NextUp.xcconfig` | Bundle ID、URL Scheme、Widget kind |
| `docs/ACCEPTANCE.md` | 验收记录 |

标识只改 xcconfig。测试会在 Swift 里的占位值和配置不一致时失败。

当前用本机目录共享数据，不需要 Apple ID。App Group 的 entitlements 留在工程里，还没有启用。
