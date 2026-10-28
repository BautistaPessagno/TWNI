// swift-tools-version:5.10
// Test harness for the platform-independent logic in TWNI/Core.
// The app target compiles those same files directly; this package only exists
// so the logic can be unit-tested with `swift test` (works on macOS and Linux).
import PackageDescription

let package = Package(
    name: "TWNICore",
    targets: [
        .target(name: "TWNICore", path: "Sources/TWNICore"),
        .testTarget(name: "TWNICoreTests", dependencies: ["TWNICore"], path: "Tests/TWNICoreTests"),
    ]
)
