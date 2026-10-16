# Final implementation review

Review base: `4667404ee109a0eb373d1546e9bcc0d0e21a4062` (approved planning seed). Reviewed integration: `5bac844723eb6c5a944c5a78a5cc7d36eaf68fb1`. Comparison: `git diff 4667404...5bac844`; 23 implementation/merge commits. Both reviewers ran independently and read the repository standards and approved specification.

## Standards

Standards review — pinned HEAD 5bac844723eb6c5a944c5a78a5cc7d36eaf68fb1

Reviewed the 42-file diff against 4667404ee109a0eb373d1546e9bcc0d0e21a4062 and its 23 commits. Read AGENTS.md, docs/agents/{issue-tracker,triage-labels,domain}.md and GLOSSARY.md. No ADRs or additional coding standards were present. No native UI checks were run.

Documented-standard breaches: none found in introduced changes. Specs/issues retain the required .scratch/<feature>/ layout and allowed triage statuses; completion is recorded separately through Resolution. The “resolved” instruction concerns wayfinding decision tickets, not these implementation tickets. Canonical domain distinctions remain intact. No tooling-enforced formatting findings are included.

Baseline smells (judgment calls, not repository-rule violations):

- Duplicated Code — scripts/check-switcher-interaction.sh:7–24 and scripts/check-switcher-native.sh:7–24 contain identical fixture construction/signing, beginning `for name in A B; do` and ending `codesign --force --sign - --identifier "dev.yifeng.DockEnhancedSwitcherFixture$name" "$fixture_dir"`. A fixture packaging change must be repeated in both. Extract one shared fixture builder and let each script select its check mode.
- Duplicated Code — Sources/DockEnhanced/WindowSwitcher.swift:399–409 and :485–496 repeat nonactivating-panel setup: `panel.level = .popUpMenu`, `panel.isOpaque = false`, `panel.backgroundColor = .clear`, shadow/deactivation/release settings and `.canJoinAllSpaces/.fullScreenAuxiliary`. A small shared panel factory would keep behavior consistent while preserving the failure notice’s mouse handling and title.

Concrete correctness concern (not a documented-standard violation):

- [P2] Sources/DockEnhanced/Accessibility.swift:47,51–60,153–159 retain every observed AX window until its entire application exits. `entries[pid, default: []].append((element, next))` has no per-window removal; each inventory then appends all `knownElements` and rereads their attributes. Repeatedly opening/closing windows in a long-lived browser/editor permanently grows retained objects and scan work, even though closed entries never become candidates. Prune identities only after a definitive invalid-element result (not absence from AXWindows, which would break accepted full-screen retention), and verify repeated create/close cycles stop increasing the registry and inventory work.


## Spec

Two actionable behavior gaps remain against the approved specification:

1. **[P2] Empty inventory falls through to native application switching.** `Sources/DockEnhanced/WindowSwitcher.swift:167` returns `false` when `candidates.isEmpty`, so the otherwise available event hook passes Command+Tab to macOS. With running windowless applications, this can activate an application despite having no eligible target. Spec line 144 says: “没有候选时结束增强选择，不显示空面板、不激活任意应用”. The native fallback authorized by spec line 176 concerns unavailable control capability, rather than an available switcher with an empty list. Consume the gesture without activation when the available switcher's inventory is empty, and cover that native-adapter path.

2. **[P2] Geometry is not refreshed when the hosting display remains connected.** The screen-configuration observer at `Sources/DockEnhanced/WindowSwitcher.swift:55–58` checks only whether the original screen disappeared. The panel is rebuilt/repositioned only for a changed candidate identity list, so a resolution or usable-frame change during selection can leave it at its old size/position or partly offscreen. Spec line 155 says: “屏幕配置变化应刷新可用几何”; line 150 also requires “以该屏幕可用空间居中并约束面板边界”. Recalculate the current host screen's available geometry and relayout the existing selection on configuration changes, while retaining cancellation for removal.

No unauthorized scope expansion found. Implementation and packaging were subsequently authorized, and the documented cold-start full-screen discovery boundary was explicitly accepted. Two ordinary desktops, a second physical display, other macOS versions, third-party conflicts, Reduce Motion enabled, and actual TCC revocation remain accurately disclosed validation gaps; they are not evidence of implementation failure. The recorded original Dock runtime failures include baseline/intermittent behavior, so they do not establish another regression here.


Initial findings: Standards — 0 documented violations, 2 duplication judgments, 1 P2 lifetime concern; Spec — 2 P2 behavioral gaps. Highest issue within each axis: retained closed-window identities (Standards), empty-inventory activation and stale display geometry (Spec).

## Resolution

All five findings were fixed by a single implementer on `codex/command-tab-review-fixes`, fixed tip `431587b4b663a272eec35014a3514c4d57722a03`, integrated by `794faf802a847f9924946c36b5551e1af1a49136`. See [fixes and red→green evidence](07-review-fixes.md).

### Standards follow-up

定向复核：通过，无剩余行动项。

固定修复 tip：431587b4b663a272eec35014a3514c4d57722a03；比较范围 be9befb...431587b。仅复核原报告三项，未扩大范围，未运行原生 UI。

1. AX 身份清理：Accessibility.swift 仅在具体窗口的实际 AXRole 查询返回 invalidUIElement 后移除对应 CFEqual 身份。AXWindows 未报告窗口不会删除；owner 查询失败/超时提前返回时不会清理，窗口角色查询的其他失败也不清理。保留 warm full-screen 身份，单调递增 ID 不复用。原先关闭窗口长期积累的问题已解决。
2. 共享夹具构建：两个检查脚本都调用 scripts/lib/switcher-fixtures.sh 的 build_switcher_fixtures；原有复制、plist 字段、签名及 A/B 路径保持一致。原重复逻辑已消除。
3. 面板工厂：两个面板均使用 makeSwitcherPanel；公共配置集中，标题分别传入，失败提示显式 ignoresMouseEvents=true，正常选择面板保持 false。原重复逻辑已消除。

证据复核：读取固定 tip 的 validation/07-review-fixes.md 与 WindowSwitcherReviewCheck.swift。新增真实 AX 检查覆盖八次创建/关闭后注册表回到基线、八个退休身份不复用、owner timeout 保留身份，以及成功 AXWindows 查询遗漏普通窗口的全屏场景仍保留两个有效身份。记录报告最终检查通过；本次结论基于代码及该既有证据，未独立重跑原生检查。


### Spec follow-up

# Spec review follow-up

Reviewed fixed tip `431587b4b663a272eec35014a3514c4d57722a03` against `be9befb`, limited to the two original spec findings. Both are resolved; no remaining action items in this scope.

- **Empty healthy inventory:** The native switcher now cancels obsolete work, consumes the Command+Tab press, and retains the Tab release for consumption. It creates no selection or empty panel. `DockService.handle` still calls this handler only while `switcherAvailable` and Accessibility access are true, so disabled/unavailable enhancement continues to pass the native shortcut through. The focused check covers press/release consumption, unchanged exact source focus, hidden panel and disabled fallback.
- **Same-display geometry change:** The screen observer resolves the original host by display identity, updates that host and its usable frame, and renders the existing frozen session. Panel rebuilding now also checks usable-frame changes, recomputes columns, bounds and centering, and scrolls the selected card into view. Neither candidate order nor selected identity is changed; removal still cancels. The focused check exercises a 3→2-column reflow with the same host/order/selection/source focus and a visible selected card.

Validation record `07-review-fixes.md` accurately distinguishes the injected usable-frame observation from a physical display change and records red/green focused checks. This follow-up inspected source and evidence only; it did not run native UI or change system state. It makes no additional multi-display or scale-compatibility claim.


Final findings: Standards — 0 remaining actionable findings; Spec — 0 remaining actionable findings. Original 2 duplication judgments and all 3 P2 concerns are resolved. Environment gaps and original Dock runtime intermittency remain disclosed in validation 05/07.
