# Focus Browser

A tiny macOS menu-bar app that automatically switches your **default web
browser** based on the active **Focus** mode. Example: in *Work* Focus your
default becomes Chrome; in *Personal* Focus it becomes Safari.

Set it up once and it runs in the background — no interaction needed afterward
except macOS's own confirmation dialog when the browser actually changes.

## How it works

macOS has **no public API to read the currently-active named Focus**, and the
official `SetFocusFilterIntent` (Focus Filters) API is reportedly broken for
list-selection on macOS 26.5. So Focus Browser reads the system's own Focus
state files:

- `~/Library/DoNotDisturb/DB/Assertions.json` — the active Focus mode id
- `~/Library/DoNotDisturb/DB/ModeConfigurations.json` — id → Focus name

These are protected by TCC, so the app needs **Full Disk Access** (a one-time
grant). When Focus changes, the app calls
`NSWorkspace.setDefaultApplication(toOpenURLsWithScheme:)`, which triggers
macOS's standard "change your default browser?" confirmation — the only
supported way to switch the default browser.

The browser is only changed when it actually differs from the current default,
so you won't get redundant dialogs.

## Build & install

```sh
./build.sh          # build only  → build/Build/Products/Release/FocusBrowser.app
./build.sh install  # build + copy to ~/Applications and (re)launch-ready
```

Requires Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

## First-run setup

1. Launch the app — a moon icon appears in the menu bar.
2. Click it → **Open Full Disk Access Settings…** and enable *FocusBrowser*.
   (You may need to quit & relaunch after granting.)
3. Toggle each Focus once (in Control Center) so the app learns their names.
4. In the menu, pick a browser for each Focus, and for **No Focus**.
5. Enable **Launch at login**.

That's it — switch Focus and your default browser follows.

## Notes / limitations

- Reading Focus relies on undocumented files; a future macOS could change their
  layout (parsing is defensive to soften this).
- The app is ad-hoc signed. Gatekeeper may require right-click → Open the first
  time, and Full Disk Access must be granted manually.
- If Apple fixes `SetFocusFilterIntent` on macOS 26.x, the detection engine
  could be swapped for Focus Filters to drop the Full Disk Access requirement.
