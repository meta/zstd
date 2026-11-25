// swift-tools-version:5.5
// A Swift package that depends on zstd and uses its static-only API.
// Run it with: swift run --package-path tests/swift
import PackageDescription

let package = Package(
    name: "StaticAPI",
    dependencies: [ .package(name: "zstd", path: "../..") ],
    targets: [
        .executableTarget(
            name: "StaticAPI",
            dependencies: [ .product(name: "libzstd", package: "zstd") ],
            path: ".",
            sources: [ "main.swift" ])
    ]
)
