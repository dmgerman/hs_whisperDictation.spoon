# Reload Hammerspoon

Reload the Hammerspoon configuration and verify it's ready.

## Important

When `hs.reload()` runs, Hammerspoon terminates its Lua state and restarts. This breaks the IPC connection that the `hs` command-line tool uses, causing the command to hang.

**Do NOT run:**
```bash
hs -c "hs.reload()"  # This will hang!
```

**Instead, run reload in background:**
```bash
timeout 5 hs -c "hs.reload()" &
sleep 2
timeout 5 hs -c "print('ready')"
```

The "message port was invalidated" error is normal and expected during reload.

## Steps

1. Run the reload command in background
2. Wait 2 seconds for Hammerspoon to restart
3. Verify Hammerspoon is responsive
4. Check console for any errors

```bash
timeout 5 hs -c "hs.reload()" &
sleep 2
timeout 5 hs -c "hs.console.getConsole()" 2>&1 | tail -10
```
