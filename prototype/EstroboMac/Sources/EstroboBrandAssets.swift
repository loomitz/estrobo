import AppKit
import Foundation

@MainActor
enum EstroboBrandAssets {
    struct ResourceDescriptor: Equatable {
        let name: String
        let fileExtension: String
    }

    static let resourceSubdirectory = "Brand"
    static let lockupResources = [
        ResourceDescriptor(name: "EstroboLockupLight", fileExtension: "pdf"),
    ]
    static let markResources = [
        ResourceDescriptor(name: "EstroboMark", fileExtension: "pdf"),
        ResourceDescriptor(name: "EstroboMark@2x", fileExtension: "png"),
    ]
    static let menuBarMarkResources = [
        ResourceDescriptor(name: "EstroboMenuBarMark", fileExtension: "svg"),
    ]

    static let lockupImage = loadLockup()
    static let markImage = loadMark()
    static let menuBarMarkImage = loadMenuBarMark()

    static func loadLockup(in bundle: Bundle = .main) -> NSImage? {
        loadLockup { resource in
            bundle.url(
                forResource: resource.name,
                withExtension: resource.fileExtension,
                subdirectory: resourceSubdirectory
            )
        }
    }

    static func loadLockup(
        resolving resolve: (ResourceDescriptor) -> URL?
    ) -> NSImage? {
        load(resources: lockupResources, resolving: resolve)
    }

    static func loadMark(in bundle: Bundle = .main) -> NSImage? {
        loadMark { resource in
            bundle.url(
                forResource: resource.name,
                withExtension: resource.fileExtension,
                subdirectory: resourceSubdirectory
            )
        }
    }

    static func loadMark(
        resolving resolve: (ResourceDescriptor) -> URL?
    ) -> NSImage? {
        load(resources: markResources, resolving: resolve)
    }

    static func loadMenuBarMark(in bundle: Bundle = .main) -> NSImage? {
        loadMenuBarMark { resource in
            bundle.url(
                forResource: resource.name,
                withExtension: resource.fileExtension,
                subdirectory: resourceSubdirectory
            )
        }
    }

    static func loadMenuBarMark(
        resolving resolve: (ResourceDescriptor) -> URL?
    ) -> NSImage? {
        guard let image = load(resources: menuBarMarkResources, resolving: resolve) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private static func load(
        resources: [ResourceDescriptor],
        resolving resolve: (ResourceDescriptor) -> URL?
    ) -> NSImage? {
        for resource in resources {
            guard
                let url = resolve(resource),
                let image = NSImage(contentsOf: url),
                image.isValid
            else {
                continue
            }

            image.isTemplate = false
            return image
        }

        return nil
    }
}
