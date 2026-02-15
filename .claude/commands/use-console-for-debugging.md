# Debug Hammerspoon via console

Use the console to debug Hammerspoon at running time

## Steps

hs.console gives you access to the console. 

For example, use this command to retrieve the last 10 
lines in the console

```bash
timeout 5 hs -c "hs.console.getConsole()" 2>&1 | tail -10
```
