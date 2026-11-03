// swift-tools-version: 5.9
// ModemOS: the user's own fake OS, shown as HuskPatch's interface when "ModemOS" is on in Appearance.
// Its own module so its names (Theme, HomeLayout, OSSettings...) stay apart from HuskPatch's.
import PackageDescription

let package = Package(
    name: "ModemOS",
    platforms: [.iOS(.v16)],
    products: [.library(name: "ModemOS", targets: ["ModemOS"])],
    targets: [.target(name: "ModemOS")]
)
