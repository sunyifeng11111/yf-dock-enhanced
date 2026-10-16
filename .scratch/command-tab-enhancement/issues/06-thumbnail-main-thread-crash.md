# 06: 修复 Command+Tab 缩略图更新时的偶发崩溃

Type: bug
Status: ready-for-agent
Blocked by: None
Resolution: fixed and installed as 0.6.1/build12; installed-app authorization subsequently confirmed

## Problem

用户报告在 Command+Tab 切换窗口时偶发退出。2026-10-16 的四份安装版 0.6.0/build11 报告（17:04:57、17:05:18、17:06:31、17:11:26）均为 SIGABRT；触发线程是 cooperative worker，栈为 `PreviewImages.captureWindows` → image publisher → `DockService` → `WindowSwitcherPanel.updatePreviewImage` → `SwitcherCard.update(image:)` → AppKit 约束／frame 异常。未复制含系统标识的完整报告。

## Feedback loop and diagnosis

最小回归入口 `--check-thumbnail-delivery` 使用本进程的单个临时窗口，经过真实 ScreenCaptureKit、共享图片缓存、生产 DockService 图片桥和可见切换卡片。界面先在主线程完成布局；在界面更新入口断言线程约束，提前捕捉与真实崩溃相同的跨线程调用。无需全局监听、不切换用户窗口、不更改偏好或权限、不保存截图。

修改生产代码前运行 `.build/debug/DockEnhanced --check-thumbnail-delivery`，连续三次均为 exit 1：`FAIL: actual screenshot completion reached switcher UI on a background thread`。单窗单截图即可重现，无需取消／重建会话。

排名假设：1. async nonisolated 截图函数在 await 后从 worker 调用图片回调；2. 原受控截图测试在 MainActor 返回，遗漏真实系统执行器；3. 旧会话回调与面板重建竞争。最小场景没有取消／重建，排除第三项为本次崩溃必要条件。修复第一项后同一失败入口立即转绿，也解释原测试为何漏检。

## Fix

对截图函数、Capture 类型和 current/publish 回调明确声明 MainActor，保持截图后的有效性检查、图片缓存写入及两种预览通知在同一执行器。只在外层建立 MainActor Task 不会隔离被调用的 async nonisolated 函数。不通过额外 fire-and-forget 队列发布，避免改变完成顺序或让旧图片绕过 generation 检查。系统截图仍异步等待。

受控测试适配器同步声明相同的 actor 合约。新增 `scripts/check-thumbnail-delivery.sh --stress`：以 release 优化编译生产实现，包含专用 DEBUG 检查入口，连续捕获并更新 50 次实际卡片。原 40 窗键鼠检查可传 `--skip-compositor-capture`，本次不保存桌面合成图。

## Validation

- 修复后最小真实截图入口：通过。
- Debug 连续 50 次真实截图／可见卡片更新：通过；每次均在主线程，图片确实出现在卡片视图中。
- DockCoreChecks：50 checks / 0 failures。
- 偏好／图像生命周期：16 checks / 0 failures，包含撤权、在途结果失效、重新授权、最小化缓存与 64 张上限。
- 实际 40 窗口 Command+Tab、方向键、滚动、Enter、鼠标及取消：通过，面板实测 126ms；未保存合成截图，结束后恢复原前台和鼠标。
- Release 优化的真实截图压力检查：50 次通过；使用独立 scratch 目录包含检查入口，不改变正式 Release 包的编译条件。
- 共享服务：39 项通过，包含三个开关的全部八种组合和可见图片清除。
- Debug／Release 构建、脚本语法、差异检查及正式包严格签名检查通过。
- 已备份并替换 `/Applications/Dock Enhanced.app` 为 0.6.1/build12，安装后的 Info.plist 与可执行文件哈希均与验证后的源码包一致。旧版备份：`~/Library/Application Support/Dock Enhanced/Backups/0.6.0-20261016-171748/Dock Enhanced.app`。
- 安装版设置已确认显示 0.6.1，当前“等待辅助功能授权”。真实安装版的快捷键复测依赖重新授权，不能将源码夹具通过扩大为安装版已授权通过。未修改系统授权、登录项、AGENTS.md 或用户偏好。

## Comments

- 2026-10-16：用户明确指出触发操作为 Command+Tab 切换窗口。按 diagnosing-bugs 建立失败先行的真实截图回路；未变更 AGENTS.md 或其他用户文件。
- 2026-10-16：后续材质调整任务开始时，安装版 0.6.1 的实际设置页已显示“正在运行”“增强可用 · 窗口缩略图已启用”，原授权待办已解除。后续版本的授权状态由任务 07 单独记录。
