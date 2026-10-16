# 07: 对齐 macOS 27 的悬浮玻璃外观

Type: visual improvement
Status: ready-for-agent
Blocked by: None
Resolution: superseded by user-requested restoration of 0.6.1 appearance; installed as 0.6.3/build14

## Request

用户指出 Command+Tab 面板与 Dock 悬停预览的毛玻璃和原生 Dock／系统 Command+Tab 不一致，要求与 macOS 27 一致。两处继续共用背景工厂，卡片内容、排序与切换规则保留。

## Material decision

原实现使用公开 NSGlassEffectView regular 材质，表现明显偏厚。先试用公开 clear 材质后，在同一受控背景上与真实系统 Dock／系统 Command+Tab 对照，仍能看出模糊厚度、透光和边缘的差异。最终采用本机 macOS 27.2 上校准的系统悬浮变体 11，由系统生成玻璃亮边和背景折射，不叠加手绘描边、底色或整体透明度。

这个变体是系统专用运行时参数，不是公开 Style 枚举案例。调用只限 macOS 主版本 27，同时核验 setter/getter 的 Objective-C ABI，以及公开 clear 材质对应的基准状态；不匹配即保留公开 clear。写入后核对读回值。macOS 28 及以上自动走公开 clear；macOS 26 使用公开 clear；macOS 14–25 保留原 NSVisualEffectView 回退。原生效果的系统内部参数无法由公开文档承诺，当前选择来自实际合成输出校准。

未保留初步方案额外增加的交互弹跳；本次只调整材质。截图与回调继续遵守 0.6.1 的 MainActor 合约。

## Visual evidence

`scripts/check-switcher-native.sh --visual --glass` 创建两个专用应用共 40 个窗口，截取实际窗口缩略图，在浮于普通窗口上方的不透明测试背景上检查两种面板。背景使用已知渐变和条纹，避免把用户窗口内容透入证据；不改变系统主题、显示配置或辅助功能设置。系统原生 Command+Tab 的参考拍摄在已安装增强停止后进行，并用 Esc 取消、松开 Command。

本机环境：macOS 27.2 (26B5112a)，Apple Silicon，单个 2× 显示器，减少动态效果关闭。

- `docs/images/macos27-native-dock.png`：真实系统 Dock 参考。
- `docs/images/macos27-native-command-tab.png`：真实系统 Command+Tab 参考，只含应用图标与名称。
- `docs/images/macos27-material-calibration.png`：本机系统变体 0–11 的一次性受控校准；不是公开枚举或跨系统保证。一次性探针源码与可执行文件已清理。
- `docs/images/macos27-dock-preview-light.png`、`macos27-dock-preview-dark.png`：实际 Dock 预览面板。
- `docs/images/macos27-grid-light.png`、`macos27-grid-dark.png`、`macos27-grid-scrolled.png`、`macos27-row.png`、`macos27-single.png`：实际切换面板。

已人工查看亮边、背景透光、明暗文字、最小化标记、横竖图比例、单行／多行和滚动。原任务 05 的历史图片未覆盖。macOS 14–26／28+、开启减少透明度、其他显示器与缩放比例未实机验证。

公开 API 参考：[NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)、[macOS 27 AppKit 设计更新](https://developer.apple.com/videos/play/wwdc2026/289/)。系统变体来自本机运行时校准，未将其描述为公开 API。

## Validation

- Debug 构建及真实玻璃合成检查通过，12 张真实专用窗口缩略图就绪。
- 最初固定 0.8 秒的夹具就绪等待曾未拿到 40 窗口；改为最长 4 秒按实际清单等待，未改变生产枚举。
- 初步 clear＋交互反馈试验的首轮快速切换检查失败，未作为通过证据。最终撤去额外交互改动、采用校准材质后，完整 40 窗口检查通过：快速往返、延迟显示、来源焦点保留、方向键、滚动、Enter、鼠标选择与取消；面板实测 129ms（5ms 采样）。未归因为某一个未经证明的时序原因。
- 最终 Release 构建通过；核心规则 50 项／0 失败。
- Debug 与 Release 优化版本均通过真实截图 → 可见卡片的主线程回归；包含最终材质桥接调用，未出现异常。
- 0.6.2/build13 正式 Release 包严格签名校验通过，已替换 `/Applications/Dock Enhanced.app` 并启动；安装后的 Info.plist 与可执行文件哈希与源码包一致。旧版备份为 `~/Library/Application Support/Dock Enhanced/Backups/0.6.1-20261016-174527/Dock Enhanced.app`。
- 安装版实际设置显示 0.6.2、“等待辅助功能授权”，通用页同时提供辅助功能与屏幕录制授权按钮。未自动改动系统授权；当前安装版的启用仍依赖用户重新授权，不能把有权限的受控检查扩大为该安装版已授权。

## Comments

- 2026-10-16：按用户反馈调整系统材质并完成同背景参考拍摄。未更改 AGENTS.md、系统权限或用户偏好。

- 2026-10-16：用户要求“恢复之前的样式”。两种面板恢复 0.6.1 的公开 regular 材质，移除系统专用运行时变体；保留 MainActor 崩溃修复、窗口切换功能及历史验证工具。以 0.6.3/build14 打包，避免版本倒退。上方截图与材质结论为 0.6.2 历史记录。
- 2026-10-16 恢复验证：PreviewPanel.swift 与 0.6.1 提交 221af53 完全一致；PreviewImages.swift 的主线程修复仍与该提交一致。Debug／Release 构建通过，真实截图更新可见卡片的主线程回归通过（1 次）。安装包签名校验通过；安装文件与打包文件哈希一致。旧版 0.6.2 备份在 `~/Library/Application Support/Dock Enhanced/Backups/0.6.2-20261016-175104/Dock Enhanced.app`。已启动安装版并从设置确认版本 0.6.3，当前显示“等待辅助功能授权”；未修改系统权限。
