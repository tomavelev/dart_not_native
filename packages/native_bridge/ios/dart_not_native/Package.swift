// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The same three Swift files the podspec beside this directory builds: an app
// with Swift Package Manager turned on gets them from here, and one without
// gets them through CocoaPods. Nothing else is declared because nothing else
// is needed - the frameworks the renderer imports (UIKit, WebKit, MapKit,
// AVFoundation, CoreText) are the system's, and the icon font is read from
// the app's Flutter assets rather than bundled with the plugin.
let package = Package(
    name: "dart_not_native",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "dart-not-native", targets: ["dart_not_native"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "dart_not_native",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
