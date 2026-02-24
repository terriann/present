# Fix #63: Add Gatekeeper Workaround to Beta Release Notes

## Phase 1 (only phase): Add release header template and update script

### 1a. Create `Scripts/beta-release-header.md`

Static markdown template containing:

1. **DMG download guidance** (top of file): A line similar to "If you're not sure which file to download, grab **Present.dmg** — you can ignore the other files."
2. **Gatekeeper workaround section**: `## Before you launch Present` heading with:
   - Brief explanation: beta is ad-hoc signed, not yet notarized with Apple Developer ID
   - The `xattr -cr /Applications/Present.app` command in a code block
   - Note that this is temporary, referencing #62 for proper signing

### 1b. Update `Scripts/beta-release.sh`

- Add `--notes-file "$SCRIPT_DIR/beta-release-header.md"` to the `gh release create` call
- Keep `--generate-notes` — gh CLI prepends the notes-file content before auto-generated changelog

### Acceptance criteria mapping

- [x] `xattr -cr` command in release notes → in template
- [x] Brief explanation of why → in template
- [x] References #62 for proper signing → in template
- [x] Workaround appears before feature changelog → `--notes-file` content is prepended by gh CLI
- [x] DMG download guidance at top → first line of template

### Unresolved questions

- Exact wording preference for the download guidance line? (Will draft and you can adjust)
