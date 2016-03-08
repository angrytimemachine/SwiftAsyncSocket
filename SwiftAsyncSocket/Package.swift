import PackageDescription

let package = Package(
    name: "SwiftAsyncSocket",
    targets: [],
    dependencies: [
                      .Package(url: "../../CIfaddrs", majorVersion: 1)
                      ]
)
