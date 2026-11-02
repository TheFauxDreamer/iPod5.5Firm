# iPodFirm on an Intel Mac with macOS 11

This note records the research to operate the app on an old Intel MacBook Pro. The Mac cannot use a version after macOS 11.7.11. The research started on 2 November 2026.

The status is research only. No port exists. The test on the old Mac is not done.

## Result

The work is possible. The estimate is 6 to 10 days for one engineer, then tests on the old Mac. This value is an estimate, not a measurement.

The gate test in this note decides if the work can continue. Do the gate test first.

The planned branch is `macos-11-intel`. The planned test app is "iPodFirm Legacy Test". The deployment target on `main` stays at macOS 14.

## Errors against macOS 11

The app now needs macOS 14 and Apple silicon. The sources were type-checked with the target macOS 11 at commit `c73cc5f`. No build was done.

| Target | Errors | Note |
|---|---|---|
| `IPodFWKit` | 3 | All are `.formatted` in `Patcher.swift`. The result is the same for arm64 and x86_64. |
| `ipodfw-helper` | 1 | `setCodeSigningRequirement` needs macOS 13. |
| `iPodFirm` | 505 | One file at a time, with the `SwiftUIMacros` plugin. Target: arm64. |

The app errors by the first macOS version that has the API:

| macOS | Errors |
|---|---|
| 12 | 278 |
| 13 | 124 |
| 14 | 85 |
| 27 | 18 |

The 18 errors with macOS 27 are from `buildBlock`. The cause is not known.

The largest groups of errors:

| API | Errors |
|---|---|
| `foregroundStyle` and `secondary` | 166 |
| `GridRow` and `Grid` | 26 |
| `Form` with `.grouped` style | 26 |
| `Button` with `role` | 19 |
| `LabeledContent` | 13 |
| `borderedProminent` | 13 |

The app type-check used the arm64 module of `IPodFWKit`, because no x86_64 module exists. Thus the app has no x86_64 count.

## Tools

| Fact | Evidence |
|---|---|
| Xcode 27 does not support macOS 11. Its minimum is macOS 12. | `SDKSettings.json` of `MacOSX27.2.sdk` and [Apple](https://developer.apple.com/support/xcode/) |
| The 26.5 SDK supports macOS 11 and x86_64. | `SDKSettings.json` of `MacOSX26.5.sdk` in the Command Line Tools |
| A small SwiftUI program with `@State` and `async` links for `x86_64-apple-macos11.0`. | The Xcode 27 `swiftc` with the 26.5 SDK |
| The compiler from the Command Line Tools cannot link x86_64. | Its compatibility libraries have only arm64 and arm64e |
| `libswift_Concurrency.dylib` for macOS 11 has x86_64. | `lipo -archs`, in `swift-5.5/macosx` in Xcode |

macOS 11 does not include `libswift_Concurrency.dylib`. The app must include the library. `mac/scripts/build-app.sh` has no copy step for it.

The link test does not prove that a program starts on macOS 11. Only the old Mac can prove this.

## Risks

- **Signature.** The release build has an ad-hoc signature and the hardened runtime. [A report](https://developer.apple.com/forums/thread/722809) says that this combination stops `libswift_Concurrency.dylib` from loading on macOS 11.
- **Patch compiler.** `Patcher.compile` runs `xcrun clang` on the Mac of the user. The old Mac must have the Command Line Tools. An older clang can give a different patch size from the value in `patch.json`. A patch can also fail to compile.
- **`diskutil`.** `Device.swift` reads the `diskutil` output. The output on macOS 11 is not compared. A wrong result here is a risk to the flash.
- **Toolchain.** The Xcode 27 compiler with the 26.5 SDK is not a documented combination. A future Xcode can remove the SDK or the x86_64 libraries.

## Gate test

The test kit is not in the repository. To make it:

1. Build a small SwiftUI app for `x86_64-apple-macos11.0` with the 26.5 SDK.
2. Put `libswift_Concurrency.dylib` in `Contents/Frameworks`.
3. Add the rpath `@executable_path/../Frameworks`.
4. Make three copies of the app with different signatures:
   - an ad-hoc signature and the hardened runtime
   - an ad-hoc signature and no hardened runtime
   - the hardened runtime and `com.apple.security.cs.disable-library-validation`
5. Add a script that compiles each patch with the flags in `Patcher.clangFlags`.
6. Make the script compare the size of the allocated sections with the result from the new Mac.
7. Make the script record the output of `diskutil list -plist external physical`.

The baseline from the new Mac is 19 patches with C code. All 19 compile. The total size of their allocated sections is 164720 bytes.

The test does not write to the iPod.

If no copy of the app starts on the old Mac, stop the work. The work then needs a different toolchain, and the estimate increases.

## Work after the gate test

| Step | Estimate |
|---|---|
| Build changes: deployment target, x86_64, SDK, library, signature | 0.5 day |
| Mechanical changes in a new `Compat.swift` | 1.5 to 2.5 days |
| Controls that macOS 11 does not have | 3 to 5 days |
| Privileged helper | 0.5 to 1 day |

The controls that macOS 11 does not have:

| Control | Replacement |
|---|---|
| `NavigationSplitView` | `NavigationView` and a `List` |
| `Grid`, `GridRow` | Stacks |
| `LabeledContent` | A simple wrapper |
| `Form` with `.grouped` | None. The panes will look different. |
| `.onKeyPress` | An `NSEvent` monitor |
| `.alert` with actions, `.confirmationDialog` | The old `Alert` or a sheet |
| `Canvas` | `NSViewRepresentable` |
| `.textSelection` | `NSTextField`, or no selection |

`SMAppService` and `setCodeSigningRequirement` need macOS 13. Thus the app must use `Privileged.run` on the old Mac. This path shows the password prompt and exists now. Touch ID is not available on that path.
