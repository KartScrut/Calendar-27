// swift-tools-version:5.9
import PackageDescription

// TwelveCore holds every piece of business logic that does not need a screen:
// the calendar rules, challenge catalog, progress and streak maths, the Sudoku
// engine, timer reconstruction and the daily discovery selector.
// It has no third-party dependencies and is unit-tested on its own.
let package = Package(
    name: "TwelveCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TwelveCore", targets: ["TwelveCore"])],
    targets: [
        .target(name: "TwelveCore", resources: [.process("Resources")]),
        .testTarget(name: "TwelveCoreTests", dependencies: ["TwelveCore"]),
    ]
)
