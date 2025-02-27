# Guide for contributors
- Check [PROGRESS.md] or the issues for tasks you could work on.
- Implement the task
- Submit a Pull Request.

## Code style
- [swift-format](https://github.com/apple/swift-format) is used for formatting. Use
```
swift-format -i --recursive Package.swift Sources/ Tests/
```
before submitting a PR.
- [SwiftLint](https://github.com/realm/Swiftlint) is used for linting. Use
```
swiftlint --progress Sources/ Tests/ Package.swift
```
for linting. No warnings should be shown, otherwise fix them or disable them for the
part of the code, if there are good reasons.


## Policies to keep in mind
Changes *must* work in GNOME Builder and *should* work in VSCode. If your patch only works in VSCode it will be rejected,
except if it is for a feature not supported by GNOME Builder.
If it works in GNOME Builder, but not in VSCode, it will be accepted, if and only if fixing VSCode requires non-trivial
changes. This means we follow the LSP client implementation in GNOME Builder.


## Contact
I made a matrix channel: [#mesonlsp:matrix.org](https://matrix.to/#/#mesonlsp:matrix.org) Feel free to join
