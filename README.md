<div align="center">

<img src="docs/images/logo.png" width="128" height="128" alt="Next TODO">

# Next TODO

**A small, quiet to-do list for your Mac. Write it down, see what's next, get on with your day.**

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20WidgetKit-F05138?logo=swift&logoColor=white)
![Version](https://img.shields.io/badge/version-1.0-orange)
![Privacy](https://img.shields.io/badge/data-stays%20on%20your%20Mac-2ea44f)

English · [简体中文](README.zh-CN.md)

</div>

---

## Highlights

- **Write fast.** Type a task and press Return. Paste a whole outline and it becomes a list with sub-tasks, up to three levels deep.
- **Menu bar quick add.** Add a task from anywhere. The three tasks that matter most sit right below the field.
- **Two desktop widgets.** *What's Left* counts what remains: overdue, today, later, unscheduled. *Next TODO* lists upcoming tasks by date, and you can tick one off right on the desktop.
- **Made for the Mac.** Custom keyboard shortcuts, undo and redo, small / medium / large text, light and dark appearance, VoiceOver and full keyboard navigation.
- **Private by design.** No account, no sign-in, no ads, no analytics, no network access. Your tasks never leave your Mac.
- **Speaks your language.** English, English (Australia), Français, 日本語, 简体中文, 繁體中文. It follows your system language.

## Install

Next TODO is coming to the Mac App Store. Requires macOS 15 or later.

## Get started

1. Open Next TODO and type your first task.
2. Click the menu bar icon to add tasks from any app.
3. Add a widget: click the date in the menu bar, choose **Edit Widgets**, search for *Next TODO*, and pick the medium or large size.

| Do this | To get this |
| --- | --- |
| Click a task | Add a sub-task |
| Right-click a task | Rename, set a due date, or delete |
| Paste multi-line text | A task outline with sub-tasks |
| Drag a task | Reorder it |
| Click the circle in a widget | Complete the task without opening the app |

A parent task is done only when all its sub-tasks are done. Widgets count leaf tasks only, so the numbers always match what you can actually do.

## Settings

Language, text size, keyboard shortcuts, the widget badge, and clearing today's or all tasks. Everything is saved immediately.

## Privacy

Tasks and preferences are stored in an App Group container on your Mac, shared between the app and its widgets. Files are backed up before each write, and a damaged file is never overwritten silently. See the [privacy policy](docs/PRIVACY.md).

## Build from source

Requires Xcode 26 and macOS 15 or later.

```bash
git clone https://github.com/Trade-Offf/NextUp.git
cd NextUp
open NextUp.xcodeproj
```

Run the **NextUp** scheme. To run the tests:

```bash
xcodebuild -project NextUp.xcodeproj -scheme NextUp \
  -destination 'platform=macOS' -derivedDataPath build test
```

Bundle IDs, App Group, URL scheme and version live in [`Config/NextUp.xcconfig`](Config/NextUp.xcconfig).

## Project layout

| Folder | What's inside |
| --- | --- |
| `NextUpApp` | Main window, menu bar and settings |
| `NextUpWidget` | Desktop widgets |
| `NextUpShared` | Tasks, sorting, storage and localisation shared by both |
| `NextUpTests` | Unit tests |
| `docs` | [Acceptance notes](docs/ACCEPTANCE.md), [App Store copy](docs/APP_STORE.md), [privacy policy](docs/PRIVACY.md) |

---

<div align="center">

© 2026 佳林 李. All rights reserved.

</div>
