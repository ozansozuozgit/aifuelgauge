# Contributing

Thanks for helping improve AI Fuel Gauge. This is a native macOS menu bar app
written in Swift and SwiftUI.

## Requirements

- macOS 14 or newer
- Xcode command line tools
- Swift 6

## Local Workflow

Run the test suite:

```bash
swift test
```

Run a debug build without installing:

```bash
make run
```

Build a standalone app bundle:

```bash
make package
```

Install the app into `~/Applications` and enable the LaunchAgent:

```bash
make install
```

Remove the standalone install and LaunchAgent:

```bash
make uninstall
```

## Before Opening a Pull Request

Run:

```bash
swift test
```

For packaging or startup changes, also run:

```bash
make package
```

If you change the standalone install path, LaunchAgent behavior, app bundle
metadata, or Homebrew cask, update the packaging tests in
`Tests/AIFuelGaugeCoreTests/PackagingScriptTests.swift`.

## Privacy Expectations

Do not add logs, diagnostics, screenshots, fixtures, or exports that include API
keys, auth tokens, prompt text, raw provider responses, local usernames beyond
normal paths, or account email addresses.

When adding a connector or local parser, keep exact provider/account data
visibly separate from local estimates. If a source cannot provide a reliable
quota or limit, label it as estimated or unknown instead of inventing one.
