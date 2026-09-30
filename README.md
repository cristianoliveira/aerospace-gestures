# aerospace-gestures

Map three-, four-, or five-finger macOS trackpad swipes to commands. Experimental Swift CLI; no third-party packages or network access.

## Try it

Requires macOS 13+, a multitouch trackpad, and Swift 5.9+.

```sh
swift run aerospace-gestures init   # once; does not overwrite an existing config
swift run aerospace-gestures check
swift run aerospace-gestures run
```

Swipe **three fingers down**. The default config shows an “It's hooked!” popup. Lift your fingers before trying again; press Ctrl-C to stop. Other swipes may be logged but have no default command.

This uses Apple's private `MultitouchSupport` framework. It does not suppress system gestures, and macOS may require Input Monitoring permission for your terminal. Do not use sudo.

## Guides

- [Usage](docs/USAGE.md): configure commands, listen safely, pause/reload from the menu, install, run a service, and troubleshoot.
- [Development](DEVELOPMENT.md): build, test, and contribute.
- [Architecture](docs/ARCHITECTURE.md): design and known risks.
