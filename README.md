# Claude Menu

A macOS menubar monitor for your Claude usage. It shows how much of your plan limits you have used, right in the menubar. A click opens a popover with the details.

## What it shows

- **Menubar title:** Your plan limit percentages, with a leading emoji when a limit is getting close (⚠️ warning, 🚨 critical). Choose between all limits, the highest limit only or an icon-only gauge.
- **Plan limits:** Usage and reset time for each limit.
- **This week by surface:** Where the weekly usage went.
- **Claude Code on this Mac:** Tokens, requests and estimated cost for today and the last 7 days, computed from your local session logs, including the share served from the prompt cache.
- **Extra usage:** Spend against your extra usage limit, when enabled.

The data refreshes automatically while the app runs. The popover can also launch the app at login.

## How it works

- Plan limits come from the same OAuth usage endpoint that Claude Code uses (`https://api.anthropic.com/api/oauth/usage`).
- The OAuth token is read from the macOS Keychain entry `Claude Code-credentials` through `/usr/bin/security`. You must therefore be signed in to Claude Code on this Mac. The token is only sent to Anthropic.
- Local usage is derived by incrementally scanning `~/.claude/projects/**/*.jsonl`. Costs are estimates based on a built-in price table; unknown models are counted as unpriced tokens.
- Nothing else leaves your machine.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode 16 or later)
- Claude Code signed in on the same Mac

## Build and install

```sh
make test      # run the unit tests
make app       # build "build/Claude Menu.app" (ad hoc signed)
make run       # build and (re)launch the app
make install   # install into ~/Applications and launch
make clean
```

On the first launch macOS may ask for Keychain access to the Claude Code credentials. Approve it to let the app read the token.

## Layout

- `Sources/ClaudeMenuCore`: Usage models, API client, session log scanner, pricing and formatting (unit tested).
- `Sources/ClaudeMenu`: The AppKit and SwiftUI app: status item, popover and usage store.
- `Tests/ClaudeMenuCoreTests`: Tests for the core library.

## Disclaimer

This is an unofficial tool and is not affiliated with Anthropic. The usage endpoint is not a documented public API and may change without notice.
