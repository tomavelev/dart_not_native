# Releasing

What a version means here, where it is written down, and what has to be true
before one is cut. Short, because a convention nobody can remember is not one.

## What is versioned

`packages/native_bridge` is the framework, and the only thing with a public
version. It is published from that directory; the repository root is the
example app, whose `version:` (`1.0.0+1`) is a build number for the demo and
means nothing to anyone consuming the package.

`packages/dart_not_native_bloc` is a companion with a version of its own
(0.1.0) and `publish_to: none`: it depends on the framework by path and
cannot be published before the framework is. When it is, it follows the same
rules, and its dependency becomes a version constraint.

The framework's version appears in **three** files, which must agree:

| File | Field |
|---|---|
| `packages/native_bridge/pubspec.yaml` | `version:` |
| `packages/native_bridge/ios/dart_not_native.podspec` | `s.version` |
| `packages/native_bridge/android/build.gradle` | `version` |

A CocoaPods or Gradle consumer reads the platform file rather than the pubspec,
so a version that drifts there is a real bug; `packages/native_bridge/test/release_test.dart`
fails if they disagree, and if the CHANGELOG has never heard of the version in
the pubspec.

## Semantic versioning, 0.x rules

[Semver](https://semver.org), with the usual 0.x reading while the major is 0:

- **0.x.0** - anything breaking. A node type that changes shape, a builder
  whose parameters change meaning, a renderer that stops accepting a tree it
  used to. The protocol in `nodeTypes` is the contract; widening it is a minor
  too, since every renderer must then draw the new type. The widget layer
  counts as well: a widget whose signature or behaviour moves to match
  Flutter's breaks the apps written against the old one, which is what the
  first section of the `Unreleased` changelog is.
- **0.x.y** - additions that do not break a tree already written, and fixes.

Past 1.0 this becomes ordinary semver, and the protocol's node vocabulary is
what the major number is about.

## Branches

- `main` is always releasable: every lane green. The lanes do not include
  anything that boots a device, so "green" does not mean the app starts -
  run `tool/device_check.sh android` and `tool/device_check.sh ios` before
  cutting a version. A compile cannot see an app that builds and then refuses
  to launch, which is what the iOS 26 UIScene failure did.
- Work happens on a branch named for what it is - `feat/swipe-actions`,
  `fix/ios-build`, `docs/android-device-pass` - and lands on `main` when its
  lanes pass.
- A release is cut from `main`, not from a branch.

## Tags

One tag per release, on the commit that sets the version:

```
v0.2.0
```

`v` plus the framework's version, nothing else - no `package-name/` prefix,
because this repository releases one package. Tag the commit that changes the
three version fields and moves the CHANGELOG's `Unreleased` section under the
new heading, so `git show v0.2.0` shows the release itself.

## The checklist

1. Every lane green: `flutter analyze --no-fatal-infos lib packages/native_bridge/lib`,
   the package suite, the example suite, the DOM suite in Chrome, and
   `flutter test integration_test` on an Android and an iOS device (see
   `.github/workflows/ci.yml` for the exact commands). Also, by hand, since no
   lane runs it: `flutter test` in `packages/dart_not_native_bloc`.

   The iOS half of this cannot be met today. The Swift renderer has not been
   compiled since it gained twelve node types (TODO.md §6.1), so a release
   cut now would ship an iOS half nobody has built. Either compile and run it
   first, or say so under **Known limits** in so many words.
2. Move the CHANGELOG's `Unreleased` entries under a `## <version>` heading.
   Anything still true and unfinished belongs under **Known limits** rather
   than being dropped.
3. Set the version in the three files above, in one commit.
4. `git tag v<version>` on that commit, and push the tag.
5. `dart pub publish --dry-run` from `packages/native_bridge`, then publish.

The repository is hosted, and `repository:` in the pubspec and `s.source` in
the podspec point at it, so step 5 is a decision rather than a task. Until it
is taken, the apps that use the framework depend on it by path or git, which
pins them to a checkout rather than a version - TODO.md §6.5.
