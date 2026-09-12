```When Editing
本文档作用: 工程总览 (价值主张 / 使用 / 架构 / 结构); MUST NOT 写发布流程 (→ workflow.md) / LLM 约束 (→ AGENTS.md)
遵循 AGENTS.md 文档编写规范
- 章节按需增删, 只留项目真有的; 首行一行价值主张, MUST NOT 带 LLM 提示
- 短并列项用表格; 可执行步骤 fenced + `#` 注释同行
- NEVER 写「开发」段 (VibeCoding 不向人类解释 dev 命令)
```

# jj-ice

macOS 菜单栏常驻读数, 只占一个图标: 上下行网速 + 右侧 AirPods 电量; 外加一个全局快捷键唤起的取词输入框.

## 使用

```bash
curl -fsSL https://raw.githubusercontent.com/yigegongjiang/jj-ice/main/scripts/install.sh | bash   # 装到 /Applications 并去 quarantine
```

- 手动装: 下载 [Releases](https://github.com/yigegongjiang/jj-ice/releases) 的 `jj-ice-macos.zip` → 拖 `/Applications` → `xattr -dr com.apple.quarantine /Applications/jj-ice.app`
- 全部内容画在一个 item 上: `[两行网速][间隔][电量%]`; 左右键点它均弹菜单 = 网速开关 / AirPods 电量开关 / AirPods 通知设置 / Quick Copy 开关 / Quick Copy 快捷键 / 登录启动 / Help / About / Quit (三个开关与登录启动均默认开)
- 网速两行 (上 = 上行 / 下 = 下行), 1s 刷新, 占宽 ~22pt; 只统计物理网卡 → VPN 开关不改变读数
- AirPods 电量 `xx%` 贴在网速右侧 (无耳机图标), 15s 刷新, 占宽 ~29pt; 只读单只 (双耳同步耗电); 显隐 = 开关 AND 已连接耳机 (网速只看开关): 未连接自动消失, 关开关连 15s 轮询一并停止
- 两个开关都关 → item 退化成 `ellipsis.circle`, 仍可点开菜单 (否则 Quit 无入口)
- 菜单里的 `AirPods Battery Notification...` = 编辑低电量通知 (JSON: 阈值 + 要调用的 HTTP 请求, 首次打开填模板)
- Quick Copy = 全局快捷键 (默认 ⌘Space) 在鼠标所在屏幕正中弹多行输入框: Return 把内容写进剪贴板并关闭, Shift/Option+Return 换行, Esc 或点别处取消; 菜单里 `Quick Copy Shortcut...` 改组合 (写成 `cmd+space` / `ctrl+opt+k`)
- ⌘Space 出厂属于 Spotlight → 首次用 MUST 先在系统设置里让出, 或直接改成别的组合; 不需要任何辅助功能权限
- ad-hoc 签名, 未公证, App Store 外分发; 需 macOS 26+

## 架构

Swift 6 + AppKit, 纯 `NSStatusItem` 实现, 无私有 API. `autosaveName` 托管图标位置, `UserDefaults` 存读数开关, `ServiceManagement` 管登录启动. 无第三方依赖.

分层:

<!-- prettier-ignore -->
| 层 | 目录 | 职责 |
| --- | --- | --- |
| 数据 | `Monitors/` | 读硬件值, 不碰 AppKit |
| 规则 | `Notify/` | 规则解析 + 逐格状态机 + HTTP 发送, 不碰 AppKit |
| 展示 | `Readout/` | 刷新循环 / 开关 / 绘制 / 弹窗 |
| 快捷键 | `QuickCopy/` | 全局快捷键 + 输入框 + 剪贴板 |
| 编排 | `StatusBarController` | 唯一 `NSStatusItem` + 菜单 + 登录启动 |

`MenuBarReadout` 持两条独立循环 (网速 1s / 电量 15s) 与两个开关, 任一变化就重画整张图交给 controller; `ReadoutImage` 只做绘制, 不碰状态.

- MUST 全部内容合成单张 template `NSImage`: 图 + button title 两套字体基线对不齐, 且 template 才能自动跟随明暗菜单栏
- item MUST 始终在菜单栏 (NEVER `isVisible = false`): 它是菜单与 Quit 的唯一入口; 空态画 `ellipsis.circle` 顶上
- 顺带绕开一个实测坑: AppKit 一旦 `isVisible = false` 就丢弃该 item 的 `NSStatusItem Preferred Position` 且永不回写 → 槽位被交出, 图标重现在菜单栏最左
- 首次启动 MUST 播种位置 0 (最右可用槽, `StatusBarController.seedRightmostPosition`), 否则新 item 落在菜单栏最左
- 电量列用左对齐 + 2pt 余量: `%` 的墨迹超出 `size()` 报的宽度, 右对齐时无论盒子多宽都贴着右边被裁 (实测)
- 只有 `Readout/` 与 `QuickCopy/` MAY `import AppKit`: MUST NOT 渗进 `Monitors/` / `Notify/`
- `autosaveName` 与开关 `UserDefaults` key 一经发布即冻结: 改名 = 重置用户图标位置 / 静默重开已关读数
- NEVER 接「折叠 / 隐藏菜单栏图标」类需求: macOS 27 起整条菜单栏是单一 window, 第三方 item 无 CG window, SkyLight 旧 status bar 接口全被编译成空实现, `MenuBarAgent` 由私有 entitlement `com.apple.private.menubar.allow` 把关 (需 Apple 签名) → 公开与私有路线均无解
- macOS 26 实测 `CGWindowListCopyWindowInfo` (macOS 27 更彻底, 整条菜单栏只剩 1 个 window): 全部菜单栏图标 (含第三方) 的 owner 都是 `Control Center` 进程, 无 Screen Recording 权限时 `kCGWindowName` 全 nil → NEVER 接「把读数贴到系统某图标右侧」类需求: Preferred Position 只在创建 / 隐藏→显示时被读取, 事后跟不了目标的移动 (macOS 27 的 AX 树虽然列得出每个 item 的 owner 与 frame, 但既无显隐属性也不可写 `AXPosition`)

网速采样: `sysctl(CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, <if_index>, IFDATA_GENERAL)` 取 `struct ifmibdata` 的 64 位 `if_data64` 计数器, 1s 差分.

- NEVER 用 `NET_RT_IFLIST2`: 内核对非 Apple 签名进程把计数器量化到 1 KiB 步进 + 4 GiB 回绕 (本机实测 en0 恰差 4294967296)
- NEVER 用 `getifaddrs`: 只暴露 32 位 `if_data`, 每 4 GiB 回绕
- 只累加 `en<数字>` + `IFT_ETHER` 接口: 隧道流量必经物理口, 再加 utun / ipsec 会双计并在 VPN 开关时跳变; bridge / vmenet / awdl / llw / ap / anpi / lo 同时被排除
- 计数器倒退 = 接口重建 → 只重设基线; 间隔 ≤ 0 或 > 5s (睡眠 / 定时器合并) → 只重设基线不出数; 接口消失即从基线剔除 (无增长)
- 渲染成 template `NSImage` 双行 → 自动跟随明暗菜单栏; 等宽字体 + 定宽 4 字符 (`999K` / `1.5M` / `1.4G`, 无箭头无 `/s`, kern -0.2) → 恒定 22pt, 读数变化不抖宽度; 行高取字体行高与 (菜单栏高 - 2) / 2 的较小值, 再压会裁字形

AirPods 采样: 子进程跑 `system_profiler SPBluetoothDataType -json` 解析 `device_connected`, 单次约 60ms (本机实测).

- NEVER 用私有 `IOBluetoothDevice` KVC (`BatteryPercentLeft` / `BatteryPercentCombined`) 或自行解码 BLE continuity 广播: 均无文档、跨版本变动, 后者还要蓝牙权限; 公共 API 无任何电量接口
- 只读 `device_connected` + `device_minorType ∈ {Headphones, Headset}`: 断连设备会移入 `device_not_connected` 并丢掉电量字段 → 结构上不可能显示过期读数; minorType 过滤挡掉同样上报电量的键鼠
- 取值优先 `Left` → `Right` → `Main` → `Single` (单驱动设备如 AirPods Max 只有后两者); 非 0–100 视为脏数据
- 子进程在 `Task.detached` 里跑 → 不卡主线程; 每条退出路径 `waitUntilExit()` 回收 (否则每轮攒一个 zombie); 10s 看门狗 `terminate()` 兜蓝牙栈卡死 → 退化成「无读数」而非永久冻结
- 15s 轮询: 电量分钟级才动 1%, 连接/断开表现为读数出现/消失; 无需监听 `IOBluetooth` 连接通知 (历史上有缺符号崩溃 + 连接失败也回调)

低电量通知: jj-ice 菜单里的 `AirPods Battery Notification...` 弹 `NSAlert` + `NSTextView` 编辑 JSON 规则, 原文存 `UserDefaults`; 首次打开填模板 (指向 notify 端点), 未保存 NEVER 发送.

- key: `threshold` (1-100) / `url` / `method` / `query` / `headers` / `body`; `{percent}` 替换为电量; body 仅 POST / PUT / PATCH (`URLSession` 在 GET 上直接丢弃)
- query 手动按 RFC 3986 unreserved 集转义: NEVER 用 `URLComponents.queryItems`, 实测它保留 `+` 原样 (`%` 会正确转成 `%25`) → 端点把字面加号读成空格
- 逐格触发: 阈值起每降 1% 发一次 (30 / 29 / ... / 1), 同一档 NEVER 重发 (只在严格低于已发档位时发 → 阈值内回升 1% 不算新的下降); 已发最低档落 `UserDefaults` → 重启不重发; 电量回到阈值以上清档 = 重新从头计; 读数为 nil (未连接) 既不发也不清档 → 摘下再戴上不重发
- 失败 (非 2xx / 网络错误) 不落档 → 下轮重试, 每档上限 3 次 (降到下一档重新计次), 保存规则即清档。NEVER 无限重试: 端点长期坏掉 = 每 15s 一次请求
- 规则只在加载 / 保存时解析并缓存: 逐次采样解析会让坏规则每 15s 刷一条日志
- 日志只记 host + 状态码: NEVER 记完整 url / header (可能含 token)
- `NSTextView` MUST 关 smart quote / dash / text replacement: 默认开启会把 JSON 的 `"` 换成弯引号, 解析必失败
- 弹窗是循环: 校验失败 / 测试结果都回到用户原文, MUST NOT 丢弃已编辑内容; 空文本保存 = 关通知 + 下次打开恢复模板
- `Send Test` 与真实通知共用 `makeRequest` + 同一发送函数: 分叉实现的测试证明不了任何事
- 弹窗期间 `runModal` 占住主 run loop → 所有读数刷新暂停, 关掉即恢复 (实测: 主队列 block 在模态期间不执行)。这是预期行为, MUST NOT 为此加补偿机制
- 关掉「AirPods 电量」开关会停掉喂给通知的轮询 → 此时保存规则 MUST 明确告知未生效

Quick Copy: Carbon `RegisterEventHotKey` 注册全局快捷键 → 无边框 `NSPanel` 弹在鼠标所在屏幕正中 → Return 写 `NSPasteboard.general`.

- NEVER 用 `NSEvent.addGlobalMonitorForEvents` / `CGEventTap`: 两者都要辅助功能权限, 前者还吞不掉按键 (目标 app 照样收到)。Carbon 这条既不要权限也不要 entitlement → 装完即用
- 实测 macOS 27: handler 装 `GetApplicationEventTarget()` + 热键注册 `GetEventDispatcherTarget()` 才送达; C 回调在主 run loop 被调用, 且因包级 `MainActor` 默认隔离必须标 `nonisolated` (隔离函数无法转成 C 函数指针)
- 实测: 组合被 macOS 自带快捷键占用时 `RegisterEventHotKey` 照样返回 `noErr`, 按键却永不到达 → 唯一判据是读 `com.apple.symbolichotkeys` 的 `AppleSymbolicHotKeys` (64 = Spotlight, 65 = Finder 搜索窗口, 60/61 = 输入法切换); 该 domain 在普通非沙盒进程里可读
- 被 Raycast / Alfred 这类走 `CGEventTap` 的启动器抢走则无法探测: `RegisterEventHotKey` 返回 `noErr`, 系统表里也查不到 → 快捷键弹窗 MUST NOT 声称「在工作」, 只说「已注册, 没反应就是被别的 app 抢了」
- 面板 MUST 是 `.borderless + .nonactivatingPanel` 且覆写 `canBecomeKey`: borderless 默认拒绝 key 状态 = 一个键都收不到; nonactivating 则让前台 app 始终不变 (实测 frontmost 不动), 回车后用户原地就能 ⌘V
- 因为 app 从不变成前台, `hidesOnDeactivate` 不会触发 → 点别处关闭靠 `windowDidResignKey`; 该路径 MUST NOT 回抢焦点 (用户正点向别的 app)
- `collectionBehavior` MUST 含 `.canJoinAllSpaces + .fullScreenAuxiliary`: 否则在全屏 app 里按快捷键表现为「什么都没发生」
- 先写剪贴板再关窗; 空文本只关窗 NEVER 清剪贴板 (误触不该毁掉已有内容); 每次打开 MUST 清空输入框
- 快捷键存成 `cmd+space` 这种文本, 解析与格式化往返一致; MUST 至少一个修饰键 (裸键会被全局吞掉)
- `NSApp.mainMenu` MUST 挂一个 Edit 菜单: menu bar agent 不显示菜单栏, 但 ⌘X/C/V/A/Z 的 key equivalent 正是由它解析, 没有则输入框里粘不进东西 (低电量通知的 JSON 框同此)

构建形态: SwiftPM executable, 无 xcodeproj / Storyboard / asset catalog; `.app` 由 `scripts/build-app.sh` 组装 (Info.plist + icns + ad-hoc 签名). universal (arm64 + x86_64) — macOS 26 仍覆盖部分 Intel 机型.

签名: ad-hoc (`codesign --sign -`), designated requirement 只钉 bundle identifier 不钉 cdhash. `SMAppService` 拒绝为无签名 bundle 注册登录项 → 签名是功能前提; 不钉 cdhash 则重装 / 升级不吊销用户已授权的登录项.

## 项目结构

- `Package.swift` — SwiftPM 清单: deployment target + `MainActor` 默认隔离
- `VERSION` — 版本单一信源; tag = `v` + 内容
- `Sources/jj-ice/` — 源码: `main.swift` (入口) / `AppDelegate.swift` / `StatusBarController.swift` (唯一 item + 菜单)
- `Sources/jj-ice/Readout/` — 展示层: `MenuBarReadout.swift` (循环 + 开关) / `ReadoutImage.swift` (绘制) / `AirPodsNotifyEditor.swift` (JSON 弹窗)
- `Sources/jj-ice/Monitors/` — 数据层: `NetworkSpeedMonitor.swift` (接口 MIB 采样 → 速率) / `AirPodsBatteryMonitor.swift` (`system_profiler` → 电量)
- `Sources/jj-ice/Notify/` — 规则层: `BatteryNotifyRule.swift` (JSON → 校验 → `URLRequest`) / `BatteryNotifier.swift` (逐格状态机 + 发送 + 重试上限)
- `Sources/jj-ice/QuickCopy/` — 快捷键层: `HotKeyShortcut.swift` (文本 ⇄ 键码) / `GlobalHotKey.swift` (Carbon 注册) / `QuickCopyPanel.swift` (输入框 + 剪贴板) / `QuickCopyController.swift` (开关 + 冲突探测) / `QuickCopyShortcutEditor.swift` (设置弹窗)
- `Resources/` — `Info.plist.in` (`@VERSION@` 占位 + `LSUIElement`) / `AppIcon.icns`
- `scripts/build-app.sh` — 构建 + 组装 `.app` + ad-hoc 签名; 本机与 CI 共用同一份
- `scripts/install-local.sh` — 本机预部署: 调 `build-app.sh` + 装入 `/Applications`
- `scripts/install.sh` — 一键安装脚本: 从 latest Release 下载 + 装入 `/Applications`; 无可配置项
- `make_icon.swift` — CoreGraphics 渲图 + `iconutil` 合成 `Resources/AppIcon.icns`
- `.github/workflows/release.yml` — `v*` tag 触发: 校验 `VERSION` → `build-app.sh` → 打 zip + checksums → 建 Release
