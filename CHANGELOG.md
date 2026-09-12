```When Editing
本文档作用: 面向使用者的发版记录; 唯一 changelog 文件, MUST NOT 拆分开发者版本
遵循 AGENTS.md 文档编写规范
- 写: 新功能 / 行为修复 / 体验 / 安全 / 安装迁移
- MUST NOT 写: 文件路径 / 函数名 / 依赖包名 / 重构细节
- 单条 ≤ 2 行, 单版本 ≤ 5 条; 段落: Added / Changed / Fixed / Removed / Security
- 无用户可感知变化 → 占位: `跟随版本同步发布`
- 顶部保留 `## [Unreleased]`; 每版底部补对比链接
```

# Changelog

[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) + [SemVer](https://semver.org/).

## [Unreleased]

## [0.12.0] - 2026-09-13

### Added

- Quick Copy: 按全局快捷键, 在鼠标所在屏幕正中弹出多行输入框, 回车把内容写进剪贴板并关闭 (Shift+Return 换行, Esc 或点别处取消)。
- 默认快捷键 ⌘Space, 默认开启; 菜单新增 `Quick Copy` 开关和 `Quick Copy Shortcut...` (快捷键写成 `cmd+space` / `ctrl+opt+k` 这种形式)。
- ⌘Space 出厂属于 Spotlight: 被系统占用时设置弹窗会直接说明并指向系统设置; 被 Raycast / Alfred 这类启动器占用则探测不到, 表现为按了没反应, 换个组合即可。
- 输入框与低电量通知的 JSON 编辑框现在都支持 ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z。

## [0.11.0] - 2026-09-12

### Changed

- 菜单栏从 3 个图标合并成 1 个: 网速两行, AirPods 电量直接贴在它右侧, 没连耳机就只剩网速。
- AirPods 去掉了前面的耳机图标, 只显示百分比 (定宽, 不会随电量变化抖动)。
- 左键或右键点这个图标都弹菜单 (原来的独立菜单图标已取消); 低电量通知改从菜单里的 `AirPods Battery Notification...` 打开。
- 两个开关都关掉时图标退化成一个圆点, 仍可点开菜单。
- 升级后图标位置会重置一次 (三个旧位置作废)。

## [0.10.0] - 2026-09-12

### Removed

- 移除折叠功能: 分隔符图标不再出现, 菜单栏图标不再可折叠。macOS 27 起系统层面已无可用机制 (公开与私有 API 均实测无解), macOS 26 的旧实现一并删除。

### Changed

- jj-ice 图标现在只是菜单入口, 左右键都直接开菜单; 升级后它的菜单栏位置会重置一次 (改按最右可用槽申请, 实际落点由系统决定)。
- 网速与 AirPods 电量读数不受影响。

## [0.9.0] - 2026-09-12

### Changed

- macOS 27 上折叠不再可用: 系统重写了菜单栏, 任何 app 都无法再把图标挤出屏幕。分隔符不再出现, 箭头换成圆点图标, 左右键都直接开菜单。
- 网速与 AirPods 电量读数在 macOS 27 上照常工作; macOS 26 的折叠行为完全不变。
- 想在 macOS 27 折叠图标, 只能用系统自带的展开按钮 (图标放不下时自动出现), 但无法指定隐藏哪些。

## [0.8.1] - 2026-08-19

### Changed

- AirPods 低电量通知改为逐格提醒: 从阈值起每降 1% 发一次 (阈值 30 → 30、29 … 1 各一次), 同一档不重发。
- 充回阈值以上重新从头计次; 重启不会补发已发过的档位。

## [0.8.0] - 2026-08-18

### Added

- AirPods 低电量通知: 点电量读数弹出 JSON 编辑器 (读数隐藏时走箭头右键菜单同名项), 填阈值 + 要调用的 HTTP 请求 (`url` / `method` / `query` / `headers` / `body`, `{percent}` 代入电量), 内置可直接保存的模板。
- 电量降到阈值只通知一次, 充回阈值以上才重新计次, 重启不重发; 编辑器带 `Send Test` 立即验证请求, 清空文本即关闭通知。

### Changed

- 点 AirPods 电量读数不再无反应, 改为打开通知设置; 网速读数仍为纯展示。

## [0.7.3] - 2026-08-18

### Added

- 右键箭头菜单新增 `Show AirPods Battery` 开关 (默认开, 升级后行为不变)。关掉即从菜单栏移除并停止 15s 轮询; 开着但未连耳机时仍不显示 (显隐 = 开关 AND 有读数)。

## [0.7.2] - 2026-08-18

### Changed

- 点网速读数不再弹菜单: 网速 / AirPods 电量等附属读数一律纯展示, 点击无反应。菜单 (含网速开关) 统一走右键箭头。

## [0.7.1] - 2026-08-18

### Fixed

- AirPods 断开后重新连接, 电量读数可能跑到分隔符左侧 (于是折叠时连带被隐藏)。现在每次重新出现都回到最右侧。

## [0.7.0] - 2026-08-18

### Added

- 菜单栏新增 AirPods 电量读数 `xx%`, 15s 刷新。只显示单只耳机 (双耳同步耗电), 未连接耳机时自动消失; 纯展示, 点击无反应。

## [0.6.1] - 2026-07-31

### Changed

- 网速读数改为最紧凑排版: 去掉上下行箭头与 `/s`, 单位缩为 `K` / `M` / `G`, 菜单栏占宽从 ~56pt 降到 ~22pt。上行在上, 下行在下 (悬停提示说明)。

## [0.6.0] - 2026-07-31

### Added

- 菜单栏常驻实时网速: `↑ 上行` / `↓ 下行` 两行, 每秒刷新, 读数取自物理网卡 → 开关 VPN 不会让数字跳变或双计。
- 右键箭头菜单新增 `Show Network Speed` 开关 (默认开); 点网速本身同样打开该菜单。

## [0.5.0] - 2026-07-31

### Fixed

- App 现在带签名, 修复「登录启动」注册失败; 覆盖安装升级不再吊销已授权的登录启动。
- 「登录启动」默认开启若首次失败, 下次启动会重试, 不再一次失败即永久放弃。

## [0.4.6] - 2026-07-31

### Removed

- 安装脚本不再支持自定义安装目录与版本, 固定安装 latest 版本到 `/Applications`。

## [0.4.5] - 2026-07-31

跟随版本同步发布

## [0.4.4] - 2026-07-31

### Changed

- Moved the install script to `scripts/install.sh`. Use the updated one-liner in the README; the old `install.sh` URL no longer resolves.

## [0.4.3] - 2026-07-23

### Changed

- Renamed the project to `jj-ice` (repository, app bundle, bundle identifier, release asset). Existing settings and Launch at Login reset on first launch of this version.

## [0.4.2] - 2026-05-31

### Changed

- Updated user-facing copy. App behavior is unchanged.

## [0.4.1] - 2026-05-31

### Fixed

- Fixed the arrow context menu opening in a clipped scroll mode.

## [0.4.0] - 2026-05-31

### Changed

- Restored the divider + arrow layout.

## [0.3.1] - 2026-05-31

### Fixed

- Kept the arrow visible after collapsing menu bar items.

## [0.3.0] - 2026-05-31

### Added

- Added a Help menu item.

### Changed

- Enabled Launch at Login by default on first launch.
- Removed the duplicate collapse action from the context menu.

## [0.2.0] - 2026-05-31

### Changed

- Simplified the menu bar control to a single arrow.

## [0.1.1] - 2026-05-31

### Fixed

- Fixed launch showing no menu bar items.

## [0.1.0] - 2026-05-31

### Added

- Added menu bar item collapse and restore.
- Added collapsed state persistence and optional Launch at Login.

## [0.0.2] - 2026-05-31

### Added

- Added the app icon.

## [0.0.1] - 2026-05-31

### Added

- Added the install script.

[Unreleased]: https://github.com/yigegongjiang/jj-ice/compare/v0.11.0...HEAD
[0.12.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/yigegongjiang/jj-ice/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.7.3...v0.8.0
[0.7.3]: https://github.com/yigegongjiang/jj-ice/compare/v0.7.2...v0.7.3
[0.7.2]: https://github.com/yigegongjiang/jj-ice/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/yigegongjiang/jj-ice/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/yigegongjiang/jj-ice/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.4.6...v0.5.0
[0.4.6]: https://github.com/yigegongjiang/jj-ice/compare/v0.4.5...v0.4.6
[0.4.5]: https://github.com/yigegongjiang/jj-ice/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/yigegongjiang/jj-ice/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/yigegongjiang/jj-ice/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/yigegongjiang/jj-ice/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/yigegongjiang/jj-ice/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/yigegongjiang/jj-ice/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/yigegongjiang/jj-ice/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/yigegongjiang/jj-ice/compare/v0.0.2...v0.1.0
[0.0.2]: https://github.com/yigegongjiang/jj-ice/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/yigegongjiang/jj-ice/releases/tag/v0.0.1
