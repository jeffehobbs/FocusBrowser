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

## Install

**Download the app** (recommended)

1. Grab the latest **`FocusBrowser.zip`** from the
   [Releases page](https://github.com/jeffehobbs/FocusBrowser/releases).
2. Unzip it and drag **Focus Browser** into your **Applications** folder.
3. Open it. (The build is notarized by Apple, so it opens without warnings.)

**Build from source**

```sh
brew install xcodegen           # one-time
git clone https://github.com/jeffehobbs/FocusBrowser.git
cd FocusBrowser
./build.sh install              # builds → ~/Applications/FocusBrowser.app
```

## First-run setup

1. Launch the app — a 🌙 moon icon appears in the menu bar.
2. Click it → **Open Full Disk Access Settings…**, enable **FocusBrowser**,
   then quit & relaunch it. *(macOS has no public API to read the active Focus,
   so the app reads the system Focus files, which require this one-time grant.)*
3. Your Focus modes now appear in the menu. Pick a browser for each — and for
   **No Focus** (the fallback when nothing is active). Leave any Focus on
   **"Don't change"** to ignore it.
4. Enable **Launch at login**.

That's it — switch Focus and your default browser follows. The first time it
switches to a given browser, macOS shows its standard "change your default
browser?" confirmation; after that it's automatic.

## Notes / limitations

- Reading Focus relies on undocumented files (`~/Library/DoNotDisturb/DB/…`); a
  future macOS could change their layout (parsing is defensive to soften this,
  and `~/Library/Logs/FocusBrowser.debug` enables a raw dump for diagnosis).
- The default browser is only changed when it differs from the current one, so
  you won't get redundant confirmation dialogs.
- If Apple fixes `SetFocusFilterIntent` (Focus Filters) on macOS 26.x, the
  detection engine could be swapped to it to drop the Full Disk Access
  requirement.

## Releasing

Maintainers: see [RELEASING.md](RELEASING.md) for the notarized-build workflow.
