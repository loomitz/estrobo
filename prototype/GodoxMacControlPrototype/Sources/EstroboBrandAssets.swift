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

    static let lockupImage = loadLockup()
    static let markImage = loadMark()

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
