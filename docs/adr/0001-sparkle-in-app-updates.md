# Use Sparkle for in-app updates

Dock Enhanced needs to download, replace, and restart the application through its own update flow rather than send users to a download page. Use Sparkle with a stable HTTPS feed and a separately backed-up EdDSA update-signing identity, while retaining the existing self-signed application identity; this adds a dependency and release-pipeline work in exchange for avoiding a custom privileged installer and restart mechanism.

The user accepted this choice during the design interview. A public checksum alone is not release authentication, and update signing does not provide Developer ID trust or Apple notarization. Losing the signing identities can disrupt updates or retained permissions, so future releases must reuse them.
