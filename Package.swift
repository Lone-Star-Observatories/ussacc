// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "USSACC", platforms: [.macOS(.v14)],
  products: [.executable(name: "USSACC", targets: ["USSACC"])],
  dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")],
  targets: [
    .target(name: "ACCCore"),
    .executableTarget(
      name: "USSACC", dependencies: ["ACCCore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
    .testTarget(name: "ACCCoreTests", dependencies: ["ACCCore"]),
  ], swiftLanguageVersions: [.v5]
)
