# Issue tracker: Local Markdown

Issues and specs live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`.
- The spec is `.scratch/<feature-slug>/spec.md`.
- Implementation issues are individual files at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`.
- Each issue has a `Status:` line using a role from `triage-labels.md`.
- Append comments and conversation history under `## Comments`.
- Record dependencies in a `Blocked by: NN, NN` line.

When publishing to the issue tracker, create the appropriate local Markdown file. When fetching a ticket, read the referenced file.

## Wayfinding

Use `.scratch/<effort>/map.md` for the map and one child file per decision ticket under `issues/`. Each child declares `Type:`, `Status:`, and `Blocked by:`. Claim an open ticket only when all blockers are resolved. On resolution, append the answer under `## Answer`, set `Status: resolved`, and add a link and verdict to the map.
