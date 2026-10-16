# Command+Tab 增强：跨应用窗口切换

Status: ready-for-agent

日期：2026-10-16。第一版产品范围已由用户整体确认；本规格的行为测试与真实系统验证方案也已单独确认。此状态表示需求可供后续实施使用，不表示技术可行性或实现已经验证。

## Problem Statement

用户希望沿用 Command+Tab 的操作习惯，以 Windows 风格直接查找和切换具体窗口，而不只是选择应用。同一应用打开多个窗口时，应能一步选中目标；窗口被最小化或应用被隐藏后，也应能通过同一个入口恢复并切到前台。

现有工具已经提供单应用的 Dock 悬停预览和指定窗口恢复，但尚未接管 Command+Tab，没有跨应用窗口使用历史、键盘选中态或多行窗口面板。新增功能需要与已有小预览窗保持统一视觉，并与原有两个功能分别控制。

## Solution

提供默认开启的“Command+Tab 增强”，以窗口切换器（Window switcher）替代系统应用切换器。每个实际应用窗口独占一张卡片，包括最小化窗口（Minimized window）；同一应用的不同窗口分别出现，浏览器标签页不独立出现。

快速按下并松开 Command+Tab，直接切到上一个窗口；持续按住约 0.12 秒才显示面板。按住 Command 浏览，松开确认；支持反向选择、方向键、Enter、鼠标和取消。选择过程中只更新选中窗口（Selected window），不提前恢复或激活目标。

面板在当前操作窗口所在屏幕中央展示，沿用 Dock 小预览窗的玻璃／毛玻璃、圆角、字体、缩略图比例和短暂动效。窗口按最近使用顺序跨应用平铺，多行排列，超过可用空间后滚动。

目标范围包括系统能够识别的其他桌面、其他显示器、全屏和隐藏应用（Hidden application）的正常窗口。对这些情况的可靠枚举与指定窗口激活，以及快捷键异常恢复，必须通过可行性验证；验证失败不能默默缩减已确认范围。

## User Stories

1. As a Dock Enhanced user, I want Command+Tab enhancement enabled by default, so that the new switcher is available without an extra setup step.
2. As an existing user, I want an unset switcher preference to default to enabled without changing my saved Dock preferences, so that upgrading preserves my existing choices.
3. As a user, I want one card per application window across applications, so that I can select the exact window directly.
4. As a user with several windows in one application, I want each window listed separately, so that I do not need an additional application-level selection step.
5. As a browser user, I want browser windows rather than individual tabs listed, so that the switcher stays focused on desktop windows.
6. As a user, I want minimized windows included, so that putting away a window does not make it unreachable through Command+Tab.
7. As a user, I want a confirmed minimized window restored and focused, so that selecting it completes the intended switch.
8. As a user, I want windows belonging to a hidden application included, so that Command+H does not remove them from the switcher.
9. As a user, I want confirming a hidden application's window to make that target visible and focused, so that I can resume working there.
10. As a user with several desktops, I want identifiable windows on other desktops included, so that I can reach them through the same switcher.
11. As a user with several displays, I want windows from every display included, so that I can switch without moving the pointer between displays.
12. As a user, I want full-screen windows included, so that entering full screen does not require a separate switching workflow.
13. As a user, I want normal untitled windows and independently usable dialogs preserved, so that valid work windows are not lost by overly broad filtering.
14. As a user, I want duplicate entries and internal helper windows excluded, so that every displayed card corresponds to a useful target.
15. As a user, I want menus, tooltips, and the desktop excluded, so that incidental interface elements do not clutter the list.
16. As a user, I want running applications without windows omitted, so that every entry has an actual window to select.
17. As a user, I want a quick Command+Tab press and release to return to the previous window, so that I can switch rapidly without a flashing panel.
18. As a user, I want holding Command after Tab to show the panel after approximately 0.12 seconds, so that deliberate selection provides visual guidance.
19. As a user, I want Tab to advance selection while Command is held, so that I can browse using the familiar shortcut.
20. As a user, I want Shift+Tab to select in reverse while Command is held, so that I can correct an overshoot easily.
21. As a user, I want Tab navigation to wrap between the last and first entries, so that every window remains reachable in either direction.
22. As a user, I want holding Tab to follow the system key-repeat rhythm, so that repeated selection behaves predictably.
23. As a user, I want releasing Command to confirm the selected window, so that the shortcut ends with a single unambiguous switch.
24. As a user, I want browsing cards to leave the original window active and minimized windows minimized, so that looking through choices has no window-management side effects.
25. As a user, I want arrow keys to move selection according to the card layout, so that a multi-row panel is easy to navigate.
26. As a user, I want Enter to confirm immediately, so that I can finish without waiting to release Command.
27. As a user, I want moving the pointer onto a card to select it and clicking to confirm it, so that I can combine keyboard and pointer input.
28. As a user, I want a stationary pointer to leave the initial keyboard selection unchanged, so that opening the panel does not unexpectedly change the target.
29. As a user, I want Escape or an outside click to cancel selection, so that I can dismiss the panel without the switcher activating a candidate.
30. As a user, I want windows ordered by actual recent use across applications, so that likely targets are near the start.
31. As a user, I want the first forward Command+Tab to select the previous window, so that repeated quick switching works between two windows.
32. As a user, I want separate usage history for different windows in the same application, so that application identity does not collapse my workflow.
33. As a user, I want the candidate order fixed during one selection session, so that browsing does not move targets unexpectedly.
34. As a user, I want minimized windows to retain their prior usage position, so that minimizing alone does not reorder my history.
35. As a user, I want startup ordering to place the current window first and unknown windows in a stable name order, so that the switcher is predictable before history exists.
36. As a user, I want window usage history kept only for the current utility run, so that window titles and usage records are not persisted to disk.
37. As a user, I want the panel centered on the current work window's display, so that it appears where my attention is focused.
38. As a user without a foreground window, I want the pointer's display used as the placement fallback, so that the panel still has a predictable location.
39. As a user, I want the panel to stay on the same display throughout selection, so that moving the pointer does not move the interface.
40. As a user, I want the switcher to share the existing preview's glass, typography, rounded geometry, and motion style, so that the utility feels visually consistent.
41. As a user, I want each card to identify its application and window title, so that similar window contents remain distinguishable.
42. As a user, I want a clearly visible neutral selected state, so that I know which window will be activated without a colored outline.
43. As a user with many windows, I want readable multi-row cards and vertical scrolling, so that previews are not made progressively smaller to fit everything.
44. As a keyboard user, I want the selected card automatically scrolled into view, so that the current target is never offscreen.
45. As a user, I want landscape and portrait thumbnails centered with their aspect ratios preserved, so that previews accurately represent their windows.
46. As a user, I want available cached thumbnails shown immediately and missing images replaced by icons and titles, so that image capture never blocks selection.
47. As a user, I want minimized cards labeled as minimized and shown with their last cached image when available, so that cached content is not mistaken for a live view.
48. As a user, I want thumbnails stored only in memory, so that normal switching does not create saved screenshots.
49. As a user without Screen Recording permission, I want icon-and-title switching to remain usable, so that image access is optional for window selection.
50. As a user withdrawing Screen Recording permission, I want screenshot caches cleared, so that the utility stops retaining captured imagery.
51. As a user without Accessibility permission or a working shortcut hook, I want native Command+Tab retained and the reason shown in settings, so that enabling the preference does not silently break switching.
52. As a user, I want an active selection canceled if required control capability is lost, so that incomplete input handling cannot activate an unintended window.
53. As a user, I want windows closed during selection removed and selection advanced when necessary, so that a stale card cannot target a nonexistent window.
54. As a user, I want windows created during selection deferred until the next session, so that the current list does not grow or reorder under me.
55. As a user, I want an empty candidate list canceled and a list containing only the current window to leave me where I am, so that edge cases cause no unexpected switch.
56. As a user, I want a brief restoration-failure indication without automatic substitution of another window, so that the result stays faithful to my choice.
57. As a user, I want new activity to cancel obsolete deferred activation, so that a slow restoration cannot steal focus from my next action.
58. As a user, I want an independent switcher toggle in a dedicated settings page and the menu bar, so that I can disable the enhancement and recover native Command+Tab easily.
59. As a user, I want disabling hover previews to leave the enabled window switcher functional, so that the three feature switches are genuinely independent.
60. As a user, I want the original Dock preview and click behavior preserved, so that adding keyboard switching does not disrupt existing features.
61. As a user, I want settings to explain which permissions are needed for control and which are needed for thumbnails, so that missing images are not confused with unavailable switching.
62. As a user, I want the switcher to respect the existing reduced-motion behavior, so that the new panel follows my accessibility preferences.

## Implementation Decisions

### 1. 功能控制与迁移

- 增加独立持久化的“Command+Tab 增强”偏好，默认开启。新安装与升级时没有该偏好的用户都使用开启；用户显式关闭后重启仍保持关闭。
- 不从旧总开关或现有预览／点击开关推导新功能状态，也不覆盖原有偏好。
- “悬停预览”“点击收起／恢复”“Command+Tab 增强”分别控制各自行为。任何一项启用且具备必要权限时，启动所需服务；三项都关闭时停止服务、关闭面板、清理截图和待执行的激活。
- 关闭增强功能立即取消其未完成选择、隐藏其面板、取消其待执行激活，并使后续 Command+Tab 恢复系统行为。切换现有两个开关不得重置仍在使用的切换器状态或禁用其必要能力。
- 缩略图采集由仍启用的图像消费者共同决定：关闭悬停预览时隐藏原小窗；只要增强仍启用，就不能沿用“预览关即全局停截图”的旧逻辑。两种预览均关闭后不再采集并清空截图缓存，单独启用 Dock 点击不需要屏幕录制。

### 2. 模块职责与主要验证边界

- 保留 DockCore 与原生应用层的现有分工。优先在 DockCore 增加一个面向完整窗口选择流程的行为入口，统一处理候选列表、窗口使用顺序、输入、时间、选中项和结束结果。
- 原生层负责将实际键鼠事件、窗口清单、权限状态和时钟变化转成该入口的输入，并执行其展示、取消或激活结果。测试通过这个入口验证可见行为，不为每个内部辅助函数另造测试接口。
- 复用现有窗口枚举、指定窗口恢复／激活、截图服务和卡片视觉能力；新增全局窗口范围、全局使用历史、多行布局与键盘选中态。模块名称和具体内部拆分可由实施决定，不要求提前引入新的公共框架。
- 用户已确认“可重复行为场景为主、真实窗口检查补充”的验证边界。该验证方案不把模拟系统适配器当作跨桌面或快捷键接管已通过的证据。

### 3. 窗口身份、候选范围与使用顺序

- 候选项表示具体窗口，不以应用、窗口标题或截图内容替代身份。同标题窗口分别出现，窗口改名不丢失其使用记录，失效身份不能错误复用到新窗口。
- 沿用根术语表：Recent window 是某一应用最近使用的窗口；本功能的全局窗口历史是另一种排序范围，不能用原来的每应用单个记录直接代替。
- 系统能够识别的正常窗口、正常无标题窗口和需要独立操作的对话框均可进入。排除重复条目、菜单、提示气泡、桌面及内部辅助面板，不以“没有标题”作为唯一排除条件。
- 无窗口应用不提供应用占位卡片。浏览器标签页不展开为候选项。
- 最小化、隐藏应用、全屏、其他桌面或其他显示器本身不构成排除条件。新切换器包含全屏窗口，不改变原有 Dock 点击对全屏／不可最小化窗口沿用系统行为的规则。
- 启动时当前工作窗口置前，其余无历史窗口按应用名、窗口标题稳定排列；同名条目保持确定的次序，不因异步更新反复跳动。获得实际使用历史后，已使用窗口按最近使用顺序排在无历史窗口前。
- 只有实际窗口使用／焦点变化更新历史，卡片选中、截图刷新、最小化状态读取或激活请求返回成功本身不算目标已经使用。目标切换结果需通过真实焦点状态判断。
- 正向第一次选择从当前窗口移到上一个使用窗口；反向按同一列表向前一个位置移动。若原工作窗口不在候选中，以当前可用排序选择候选，不伪造当前窗口条目。
- 一次选择开始后固定候选顺序；最小化本身不重置排序。重启工具清空历史，不将窗口标题或使用记录写入磁盘。

### 4. 选择流程与时间规则

| 场景 | 可观察结果 |
| --- | --- |
| 闲置时按 Command+Tab | 启动一次选择，确定初始候选与选中项，开始约 0.12 秒展示计时 |
| 展示前松开 Command | 立即确认当前选中项，取消展示计时，不闪出面板 |
| 持续按住超过展示阈值 | 在候选可用时显示面板；不等待缩略图生成 |
| 选择中按 Tab／Shift+Tab | 在固定顺序中向前／反向选择，首尾循环 |
| 按住 Tab | 使用系统按键重复节奏，不另设一套重复速度 |
| 按方向键／移动鼠标 | 更新同一个选中项，不激活目标 |
| 松开 Command、按 Enter 或点击卡片 | 只确认一次，结束本轮并恢复／激活指定窗口 |
| Esc、点击面板外、关闭增强或失去必要控制能力 | 取消本轮，不因切换器选择激活目标 |

- 约 0.12 秒是面板展示目标延迟，不是等待窗口扫描／截图的阻塞时长，也不是此次规格已测得的性能结果。快捷输入和界面响应不能被逐应用同步枚举或截图拖住。
- Enter 或鼠标已确认后，之后到来的 Command 松开不得再次切换；取消后的松开也不得执行先前选中项。已经结束的展示计时和异步回调不得重新打开面板。
- 浏览期间不恢复任何最小化窗口，也不切走前台焦点。点击面板外取消只约束切换器自身不激活候选，不阻止该点击按系统正常语义作用于外部界面。
- 识别切换快捷键及面板导航所需的按键／修饰键，不记录输入文字；更新原有“从不检查具体按键”的说明，避免新增能力后隐私描述失真。未用于本功能的系统／应用快捷键不得被无故屏蔽。

### 5. 键盘、鼠标与动态列表

- 方向键依据实际卡片几何位置选择邻近卡片，而非一律按线性顺序移动；不存在对应方向邻居时维持选中项。Tab 的首尾循环规则独立于方向键。
- 鼠标在本轮确实移动到卡片上才参与选中。面板出现在静止鼠标下，以及键盘滚动把卡片移到静止鼠标下，都不能擅自覆盖键盘选中。
- 键鼠共用一个 Selected window；鼠标点击必须确认实际点击的窗口，不能确认先前的键盘目标。
- 已关闭的窗口立即从本轮可用列表移除，保留其他项的相对顺序。删除选中项时顺延到下一项，必要时循环；列表空时取消。
- 本轮新出现的窗口留到下一次选择，禁止异步清单刷新将其插入当前列表并改变选择。
- 没有候选时结束增强选择，不显示空面板、不激活任意应用；只剩当前窗口时保持原状。只有一个非当前候选时仍允许确认该目标。
- 工具进入停止状态或监听中断后，不保留能够在后续事件中误提交的旧会话。

### 6. 显示器、布局与视觉复用

- 优先以选择开始时当前操作窗口所在显示器作为面板位置；没有前台窗口时使用鼠标所在显示器。正常选择过程中不跟随鼠标跨屏移动。
- 以该屏幕可用空间居中并约束面板边界，多行卡片超出面板容纳范围时纵向滚动。卡片不因数量增加而无限缩小，选中项始终自动滚入可见区域。
- 复用原小预览窗的玻璃／毛玻璃材质策略、圆角层级、字体、缩略图比例、短暂淡入淡出与减少动态效果策略。键盘选中态使用清楚的中性明暗填充，不新增彩色外框。
- 每张切换器卡片标识应用图标与居中的窗口标题，缩略图居中且保持源窗口比例；长标题截断而不撑破布局。应用图标与标题用于区分跨应用条目，不能继续只在整个面板顶部显示单一应用名。
- 卡片间距及左右外边距对称，纵横窗口均可辨识；多行、滚动、鼠标悬停和键盘选中保持统一视觉。最小化卡片在切换器中有低调但可见的“已最小化”文字，不必改变旧 Dock 小窗已确认的简约文字规则。
- 使用原生控件的可访问名称和选中信息，保持标题、选中窗口与最小化状态能被理解；选中效果需在明暗外观下可辨。
- 屏幕配置变化应刷新可用几何；若承载屏幕在选择中消失，应安全取消，避免留下不可操作的面板或切换到未经确认的目标。这属于异常清理，不改变正常选择过程中位置固定的规则。

### 7. 缩略图与内存生命周期

- 已有缓存立即显示；没有缓存先显示应用图标与标题，再异步更新可用图片。图像更新不得改变窗口身份、列表顺序、选中项或滚动目标。
- 最小化窗口只使用最后缓存的画面，不为了截图提前恢复；没有缓存则继续使用图标与标题。缓存画面不宣称是实时预览。
- 截图缓存保留现有有界内存策略，不能因全局窗口数量增加变成无限制缓存；不要求保存所有窗口的图片才能使用切换器。退出、服务停止或不再有图像消费者时清理缓存。
- 缺少屏幕录制权限时不请求新截图，仍允许图标与标题切换。权限撤销时清理共享截图缓存，并使已在途截图结果失效，避免异步完成后重新写回旧图片。
- 权限恢复后可重新异步获取图片，不以重新截图作为一次切换的前置条件。
- 正常功能不将窗口画面、窗口标题、使用历史写到磁盘或发送到网络；专用测试夹具的截图证据不改变正常功能的隐私边界。

### 8. 指定窗口恢复与焦点结果

- 复用现有指定窗口恢复／激活逻辑，必要时扩展隐藏应用与跨桌面／全屏处理。先确认目标，再执行恢复，不以激活整个应用代替激活所选窗口。
- 最小化恢复可能需要等待系统动画；沿用有界重试、就绪检查和真实焦点确认，窗口操作不得在输入事件回调内阻塞。
- 新的用户操作、新的窗口命令、取消或关闭功能，使旧的待执行激活失效。需要区分本轮确认事件与之后的新活动，不能让确认自身的 Command 松开或鼠标事件错误取消必要的恢复。
- 目标关闭或恢复失败时给简短、非阻塞提示，不自动改选另一窗口、不无期限重试、不在用户转去操作其他窗口后抢回焦点。若系统已完成部分恢复，不假定能回滚所有系统变化；必须准确判断结果而不是将请求成功当成完成。
- 对隐藏应用，至少保证所选窗口可见并获焦点；不额外承诺能够单独保留该应用其他窗口的隐藏状态。对其他桌面／全屏窗口，验证实际系统切换结果，不以界面可显示卡片代替可到达目标。

### 9. 权限、快捷键接管与故障恢复

- 偏好开启不等于增强已运行。缺少辅助功能权限、事件接管创建失败或被系统限制时，不吞掉原生 Command+Tab，设置中说明增强当前不可用的原因。
- 屏幕录制只决定图像能力，缺失时显示“图标和标题可用”对应的清楚状态，不能误报整个窗口切换不可用。
- 会话中失去必要权限、监听超时／中断、修饰键松开丢失等情况，首先使旧会话和待执行动作失效，防止误激活或卡住。恢复后后续输入从干净状态处理。
- 不把“原生回退”解释为能够可靠重放所有已被拦截的历史输入。必须验证未接管时的系统快捷键可用，以及中途故障后后续手势可用；若无法恢复，明确显示状态并提供关闭增强的现有入口。
- 安全输入、其他快捷键软件冲突及系统保留快捷键的实际行为属于验证事项，不能依据模拟测试声称已支持。

### 10. 设置、菜单栏与原功能回归

- 保留“Dock 功能”和“通用”页，新增“窗口切换”页，展示默认开启的“Command+Tab 增强”开关与已确认操作说明。保留原默认设置页、窗口尺寸调整、侧栏底部状态与退出入口。
- 菜单栏同步提供独立开关，设置与菜单栏共享同一偏好；隐藏菜单栏图标时仍可通过原有应用重开入口访问设置。
- 更新系统权限说明：辅助功能用于识别／操作窗口及快捷键增强，屏幕录制用于两类窗口缩略图。给出缺失权限的原有系统设置入口；不在每次按快捷键时重复打断用户授权。
- 增强状态应可与其他仍运行的 Dock 功能区分，不能仅因共享服务已运行就宣称快捷键接管成功。
- 继续保持原有登录自启、隐藏菜单栏图标、Dock 点击、悬停延时、上下文菜单、拖动与原生修改键点击行为。
- 新增的全屏窗口切换目标不扩大 Dock 点击收起功能的既有能力。新功能不改变原有不支持最小化时的系统回退。

## Testing Decisions

### 已确认的验证方式

用户已确认：以一组可重复操作场景验证选择、取消、排序与异常；再通过真实 macOS 窗口验证快捷键接管、最小化恢复、跨桌面／全屏和视觉一致性。

优先沿用现有 DockCoreChecks 的独立行为检查形式，在完整选择流程入口提供候选清单、模拟时间与操作序列，断言用户可见的列表、选中项、面板状态和唯一结束结果。测试不依赖真实时间睡眠、不验证私有字段或调用次数，也不为每个实现函数照抄一组测试。

系统适配层沿用现有原生窗口夹具、实际选择动作与焦点验证方式，不另造一个只验证控制器被调用的假集成入口。可扩展现有双窗口夹具形成两个独立应用的受控多窗口场景，覆盖同应用与跨应用选择。

### 行为层场景

| 场景组 | 必须验证的可观察结果 |
| --- | --- |
| 选择与排序 | 正向首次选择上一个窗口；反向、循环、两窗口往返；同应用窗口独立排序；窗口改名／同名不混淆；冷启动稳定顺序 |
| 展示计时 | 阈值前结束不闪面板；阈值后显示；截图未就绪不影响；取消／关闭后的旧计时不再显示 |
| 输入与确认 | 松开 Command、Enter、点击各自产生唯一确认；Esc／外部点击取消；确认后松开不重复执行；键盘与鼠标共用选中项 |
| 指针与网格 | 静止指针和键盘引发的滚动不抢选；实际移动可选；方向键按几何邻居移动；选中卡片保持可见 |
| 列表变化 | 关闭未选中／选中／最后窗口；按规则顺延；新窗口下轮加入；空列表与仅当前窗口无激活副作用 |
| 使用历史 | 浏览不写历史；最小化不改位置；实际焦点变化才更新；一次选择冻结顺序；重启清空，不持久化标题 |
| 异步与取消 | 旧截图、旧面板计时、旧恢复结果在失效后不生效；确认自身事件不误取消恢复；后续新活动阻止旧激活抢焦点 |
| 权限与服务 | 无录屏仍可图标切换；撤销清图且拒绝在途图片回写；缺辅助功能／接管失败不输出增强激活；中断清空会话 |
| 开关与迁移 | 默认开启、显式关闭持久化、不覆盖旧偏好；三开关全部八种组合；无图像消费者时停截图，全关闭时停止服务 |

行为测试可证明规则处理正确，不能单独证明系统原生回退、跨桌面激活或全屏兼容性。

### 原生行为与兼容性检查

1. 在受控测试窗口中真实按下 Command+Tab 并松开，验证切换的是显示卡片对应的具体窗口；分别覆盖同应用与跨应用，不只比较前台应用标识。
2. 最小化目标、在另一应用工作、选择目标：确认浏览阶段仍最小化，确认后展开、正确获焦点且短暂观察期内不自行退回来源应用。
3. 恢复过程中制造新的真实活动，验证旧恢复不会抢回焦点；覆盖 Command 松开、Enter、鼠标确认，避免某种确认路径被旧取消逻辑打断。
4. 分别验证 Command+H 隐藏应用、其他桌面、其他显示器、全屏窗口；必须包括同一应用的两个窗口位于不同桌面。分别记录枚举、选择、可见性和准确焦点结果。
5. 验证实际快捷键关闭回退、辅助功能缺失／撤销、监听创建失败／运行中失效及后续手势恢复。能够安全注入的故障自动化，安全输入和其他快捷键工具冲突按实际环境验证并记录边界。
6. 验证屏幕录制未授权时仍可切换、授权后异步补图、撤销后缓存及可见图片清除。用受控窗口做权限相关验证，不擅自重置用户已有权限或修改系统安全设置。
7. 使用相同标题、无标题标准窗口、独立对话框和内部辅助面板验证窗口过滤；验证最小化、隐藏和后台状态不会误排除实际窗口。
8. 覆盖少量及大量窗口、多个网格行和滚动，确认键盘目标可见、循环不丢项、图像加载不改选、静止鼠标不接管选中项。
9. 检查三开关全部八种组合及重启持久化，尤其是只开增强、只开点击、增强与悬停共同开，以及关闭其中一个不破坏另一个。
10. 复用原有 Dock 原生检查，确认点击收起／恢复、预览选择、原生右键菜单、带修饰键点击、拖动、预览抑制和最近窗口行为无回归。
11. 检查设置新页、菜单栏同步、默认开启和显式关闭、菜单栏隐藏后的重新打开；权限说明与实际能力一致。
12. 测量冷启动／热缓存、有许多应用或慢辅助功能响应、无截图时的输入响应。0.12 秒仅约束面板目标展示时间，报告实际结果和限制，不凭测试定时器推断真实性能。

### 视觉检查

- 以实际桌面合成的面板截图与现有小预览窗对照，检查玻璃边缘、明暗外观、中性选中态、字体、圆角、缩略图居中与比例、对称间距和最小化标记。
- 覆盖单卡、单行、多行及滚动状态，宽／竖窗口、长标题、图标替代、不同显示器缩放比例和“减少动态效果”。不能只检查布局数值或孤立窗口渲染就宣称实际玻璃效果一致。
- 验证面板出现在工作窗口所在屏幕，静止指针位于其他屏幕不改变位置；没有前台窗口时使用鼠标屏幕。

### 结果与环境记录

- 先运行已有无界面行为检查与原生回归，再执行新增检查；只在失败、新改动或未解决风险需要时重复。
- 原生检查应恢复原鼠标位置、前台应用及测试改变的窗口状态，清理测试应用；避免关闭真实用户窗口或输出其标题／内容。
- 当前项目已有“通过／失败／检查不可用”的区别。缺少权限、第二显示器、合适的桌面／全屏夹具或指定系统环境时，记录“未验证／检查不可用”及原因，不记为通过。
- 沿用现有 macOS 14 及以上支持范围和材质版本回退策略。可用宿主上的通过结果不代表所有支持系统版本已覆盖；未覆盖项在交付记录中明确列出。
- 本次只编写规格，不执行会切换窗口、移动鼠标或改动权限的原生测试，也不把旧功能曾经通过的结果登记为新功能验证。

## Out of Scope

- 浏览器标签页切换、应用分组后的第二级选择、无窗口应用的启动卡片、桌面条目。
- 第一版的自定义快捷键、面板延迟、卡片尺寸、重复速度、分组及排序偏好设置。
- 面板内关闭窗口、退出应用、批量最小化、窗口布局／移动或其他未讨论的窗口管理操作。
- 截图落盘、录像、云同步、网络服务、持久化窗口使用历史或记录用户输入文本。
- 为了生成缩略图自动恢复窗口，或承诺最小化窗口有实时画面。
- 改写原有 Dock 点击／悬停的产品行为，或用本功能把 Dock 点击的全屏窗口限制一并改变。
- 在本次规格任务中直接实现、打包、替换已安装应用或进行发布；拆分实施 tickets 属于后续工作。

## Further Notes

- 用户确认记录见同目录的[设计访谈](design-notes.md)，领域名称以根术语表为准；目前没有相关已接受 ADR 需要推翻。
- 待验证的技术条件不改变已确认的产品目标。建议先打通“真实快捷键 → 跨应用窗口选择 → 最小化恢复 → 准确焦点结果”的最小完整路径，并优先验证同应用跨桌面、全屏、安全输入与监听中断。如果证据表明现有系统能力无法满足范围，应记录具体失败场景、可复现结果与备选方案，再就必要范围变化找用户确认。
- 原有单应用窗口清单和每应用 Recent window 记录可复用，但不是全局使用历史；原有截图缓存与恢复逻辑是基础，不是新功能已兼容所有应用／桌面的证据。
- 规格发布位置为本地需求目录；Status 使用本项目的 ready-for-agent，无需再次 triage。本次没有创建实施 tickets，也没有选择需要单独 ADR 的平台锁定或不可逆架构方案。

## Comments

- 2026-10-16：用户在四轮设计问答及整体摘要后确认第一版范围。
- 2026-10-16：用户接受以可重复行为场景为主要验证入口、真实 macOS 窗口检查补充系统兼容性与视觉结果的方案。
- 2026-10-16：正式规格保存到本地需求目录，标记 ready-for-agent；新功能尚未实现或运行验证。
