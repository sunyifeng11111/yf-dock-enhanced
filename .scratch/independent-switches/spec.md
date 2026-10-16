# Independent feature switches

Status: ready-for-agent

Replace the combined Dock enhancement switch with independent “悬停预览” and “点击收起 / 恢复” switches in settings and the menu bar. Each persists separately; existing master-switch preferences supply the initial state when no individual preference exists.

- Preview off: immediately dismiss the panel, discard thumbnails, and stop captures; clicking Dock icons can still minimize/restore when enabled.
- Click control off: pass Dock clicks to macOS; hovering and selecting previews still work when enabled.
- Both off: stop the service; enabling either starts it when Accessibility permission is available.
- Keep login launch and 0.40-second preview defaults. Disable the hover-delay slider when previews are off.
- Verify the four switch combinations and persistence, then update the installed app.

## Validation

The final native integration run passes all previous Dock/menu/window checks plus: preview-only native clicks and exact preview selection; click-only minimize/restore with no visible preview or thumbnail cache; both-off service shutdown and native clicks; both-on restart. The 16 core checks pass. New async UI checks execute on the main actor, and a stale fixture from an interrupted run is not used as the foreground restoration target.

Installed 0.4.0 settings were exercised through both-on, click-only, both-off, and preview-only. Restarting the app preserved preview-on/click-off independently; both switches were then restored to on. The delay slider is disabled only when previews are off, the delay remains 0.40 seconds, and login launch remains on. The installed release currently shows pending Accessibility/Screen Recording authorization; native tests ran through the authorized development environment.
