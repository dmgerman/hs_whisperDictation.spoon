# Claude Code Instructions

## Code Quality Standards

- Always document with LuaDoc format
- Use option-style returns for "fallible" functions where appropriate

When reviewing or refactoring code, do a **complete systematic pass**:

1. **Review every file**, not just the ones immediately relevant
2. **Review every function** for:
   - Deep nesting (flatten with early returns)
   - Long functions (extract focused helpers)
   - Code duplication (consolidate into shared modules)
   - Magic numbers (lift to constants or config)
3. **Don't declare "done" until the full pass is complete**


### Checklist Before Declaring Work Complete

- [ ] Scanned all files in the module/spoon
- [ ] No functions over ~50 lines
- [ ] No nesting deeper than 3 levels
- [ ] No duplicated logic across files
- [ ] No magic numbers in logic (all in Theme/Config)
- [ ] All public APIs documented with LuaDoc

## Skills

- `/reload` - Reload Hammerspoon safely (see `.claude/commands/reload.md`)
- '/use-console-for-debugging.md' - access the console output (see `.claude/commands/use-console-for-debugging.md`)

## Lessons Learned

- 2026-02: "Done" means systematically reviewed, not "compiles and runs"
- 2026-02: **Always verify changes work before reporting success**:
  1. Make the change
  2. Reload Hammerspoon (use `/reload` skill - run in background to avoid hang)
  3. Check console/logs for errors
  4. Actually test the feature works (trigger the hotkey, open the menu, etc.)
  5. Only then report success
- 2026-02: **Hammerspoon reload hangs** - `hs -c "hs.reload()"` breaks IPC connection.
  Run in background instead: `timeout 2 hs -c "hs.reload()" &; sleep 2; timeout 2 hs -c "print('ready')"`
- 2026-02: **Never use CAPITALIZED names** for any files.
