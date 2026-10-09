// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftUIWin",
    targets: [
        // Mini SwiftUI implementation rendered with Win32 GDI
        .target(
            name: "SwiftUI",
            path: "Sources/SwiftUI",
            linkerSettings: [.linkedLibrary("User32"), .linkedLibrary("Gdi32")]
        ),
        // Live preview host: user's iOS view files are copied in by preview.py
        .executableTarget(
            name: "PreviewHost",
            dependencies: ["SwiftUI"],
            path: "Sources/PreviewHost"
        ),
        // Unmodified SwiftUI app source
        .executableTarget(
            name: "CounterApp",
            dependencies: ["SwiftUI"],
            path: "Sources/CounterApp"
        ),
    ]
)
