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

All five findings were assigned to a single implementer on `codex/command-tab-review-fixes`. Fix and validation evidence will be recorded after integration.
