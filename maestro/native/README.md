# Native device flows

Maestro flows that drive the **native renderers** on a device: a tap or a
keystroke goes through the platform's own view, across the method channel, into
Dart, and comes back as a patched view.

```sh
maestro/native/run.sh android            # every flow that applies to Android
maestro/native/run.sh ios                # …and to iOS
maestro/native/run.sh android counter    # one flow
maestro/native/run.sh ios textinput_ios --no-build   # reuse what is installed
```

For the flows *and* the integration tests in one go, use
`tool/device_check.sh android` (or `ios`), which finds the device, runs these
flows first and the integration tests after. None of this runs in CI - see
TESTING.md for why - so it is worth running by hand after a change to the
Kotlin or Swift renderers.

Each flow names the entry point it needs in an `# entry:` comment, because
every example shares one application id; the runner builds and installs that
app first. `--device` picks a specific emulator or simulator when more than one
is up.

## Why this exists

`integration_test/native_renderer_test.dart` hands both renderers one of every
node type and listens for errors. That says a renderer *drew* something - not
that anything it drew works. The gap is not theoretical: the floating-label
commit deleted the line that sends a text field's change event on Android, and
for two days every bound field there drew, focused and kept its caret while the
app behind it heard nothing. No test failed. `textinput_android.yaml` fails.

## What the flows can see

Maestro reads the platform's accessibility tree - the same one a screen reader
uses - so these flows only pass if the views are *announced* as well as drawn.
That is how the iOS renderer was found to be invisible to accessibility
entirely: a `FlutterView` answers `accessibilityElements` with Flutter's own
semantics, and UIKit takes that list instead of the view's real subviews.

`inbox.yaml` is the one that earns the lane its keep on a long list: it
scrolls ten thousand rows a long way down, checks that what arrived is real
(its own number, its own sender, an actions button that opens that row's
sheet), and scrolls back to find row 1 where it was left.

## iOS runs on a simulator, not on a phone

`run.sh ios` builds `--simulator` and installs with `simctl` on purpose: the
flows **cannot** run on a physical iOS device here. Maestro drives a real
device through an XCUITest driver it builds itself, and that build fails for
three reasons at once (2026-09-24, Maestro 2.5.1, Xcode 26 / iOS 27, log in
`~/.maestro/maestro-iphoneos-driver-build/output.log`):

- its bundle id `dev.mobile.maestro-driver-ios` belongs to mobile-dev-inc, so
  it cannot be registered to somebody else's development team - "cannot be
  registered to your development team because it is not available";
- no provisioning profile exists for it, which follows from the first;
- its `IPHONEOS_DEPLOYMENT_TARGET` is 14.0, and this Xcode supports 15.0 and
  up - an upstream break with Xcode 26, reported as Maestro issues #3608 and
  #3218.

`--apple-team-id` - which this Maestro's `--help` does not list - gets past
the first complaint and into the build, where the rest are waiting.

The first two were tried and are surmountable. Patching Maestro's own jars
(bundle id `dev.mobile.*` to a prefix that can be registered, deployment
target to 15.0) cleared both, and the build then got far enough to fail on
something else entirely:

    Build input file cannot be found: .../MaestroDriverLib/Info.plist

That is the third and it is not surmountable here: the `MaestroDriverLib`
target compiles six sources and the CLI jar ships one of them
(`AXElement.swift`), with `AXFrame`, `ElementType`, `PermissionValue`,
`PermissionButtonFinder`, `MaestroDriverLib.swift` and the `Info.plist` all
absent from the package. The library's implementation is simply not in the
release. Going further would mean vendoring Maestro's Swift sources into a
patched jar, which would be undone by the next upgrade.

The patch was reverted; Maestro here is stock. Worth knowing if anyone retries:
the bundle id has to be replaced with a prefix of exactly the same length,
because six compiled classes carry it as a string constant and cannot be
recompiled. So iOS device coverage is: the flows on a simulator, and the app
itself installed and driven by hand on the iPad.

`focus.yaml` checks the one thing a screenshot cannot tell you: whether the
renderer really moved the caret when the app asked. It taps the showcase's
"focus the name field" and "dismiss the keyboard" buttons and reads back the
*field's* own focus and blur events, which the showcase prints as
"Status: ...". Taking the `focusVersion` out of the tree fails it on both
platforms.

`a11y_android.yaml` and `a11y_ios.yaml` use that tree for what it is for:
they assert that a checkbox, a radio group and a switch are announced with
their labels *and their states*, and that tapping one moves the state a
screen reader would read. On iOS that state is a trait rather than a picture,
which is the only way it can be read at all.

The two platforms are deliberately not identical - Android floats a field's
label inside the box, iOS draws it above - so a flow that has to point at a
field is written per platform and named for it (`*_android.yaml`, `*_ios.yaml`).
Flows that only need text both renderers draw are shared.
