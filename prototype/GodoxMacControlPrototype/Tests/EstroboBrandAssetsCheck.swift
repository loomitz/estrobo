import AppKit
import Foundation

@main
@MainActor
enum EstroboBrandAssetsCheck {
    static func main() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let brandURL = projectURL
            .appendingPathComponent("Resources")
            .appendingPathComponent(EstroboBrandAssets.resourceSubdirectory)

        var lockupRequests: [String] = []
        let lockupImage = EstroboBrandAssets.loadLockup { resource in
            lockupRequests.append(fileName(for: resource))
            return brandURL
                .appendingPathComponent(resource.name)
                .appendingPathExtension(resource.fileExtension)
        }

        guard let lockupImage else {
            throw BrandAssetCheckError.missingVectorLockup
        }
        expect(
            lockupRequests == ["EstroboLockupLight.pdf"],
            "The complete Affinity lockup must be loaded without rebuilding the wordmark"
        )
        expect(
            lockupImage.representations.contains { $0 is NSPDFImageRep },
            "EstroboLockupLight.pdf must decode as a vector PDF image"
        )
        expect(!lockupImage.isTemplate, "The lockup must preserve its original brand colours")

        var vectorRequests: [String] = []
        let vectorImage = EstroboBrandAssets.loadMark { resource in
            vectorRequests.append(fileName(for: resource))
            return brandURL
                .appendingPathComponent(resource.name)
                .appendingPathExtension(resource.fileExtension)
        }

        guard let vectorImage else {
            throw BrandAssetCheckError.missingVectorMark
        }
        expect(
            vectorRequests == ["EstroboMark.pdf"],
            "The vector mark must be the first successful candidate"
        )
        expect(
            vectorImage.representations.contains { $0 is NSPDFImageRep },
            "EstroboMark.pdf must decode as a vector PDF image"
        )
        expect(!vectorImage.isTemplate, "The colour mark must not be tinted as a template")

        var fallbackRequests: [String] = []
        let rasterImage = EstroboBrandAssets.loadMark { resource in
            fallbackRequests.append(fileName(for: resource))
            guard resource.fileExtension == "png" else { return nil }
            return brandURL
                .appendingPathComponent(resource.name)
                .appendingPathExtension(resource.fileExtension)
        }

        guard let rasterImage else {
            throw BrandAssetCheckError.missingRasterFallback
        }
        expect(
            fallbackRequests == ["EstroboMark.pdf", "EstroboMark@2x.png"],
            "The Retina PNG must be used only after the PDF is unavailable"
        )
        guard
            let bitmap = rasterImage.representations
                .compactMap({ $0 as? NSBitmapImageRep })
                .first
        else {
            throw BrandAssetCheckError.invalidRasterFallback
        }
        expect(
            bitmap.pixelsWide == 92 && bitmap.pixelsHigh == 92,
            "EstroboMark@2x.png must remain exactly 92 x 92 pixels"
        )
        expect(!rasterImage.isTemplate, "The PNG fallback must preserve brand colours")

        guard
            let appBundlePath = CommandLine.arguments.dropFirst().first,
            let appBundle = Bundle(path: appBundlePath)
        else {
            throw BrandAssetCheckError.invalidAppBundle
        }
        guard
            let bundledLockupURL = appBundle.url(
                forResource: "EstroboLockupLight",
                withExtension: "pdf",
                subdirectory: EstroboBrandAssets.resourceSubdirectory
            ),
            FileManager.default.fileExists(atPath: bundledLockupURL.path)
        else {
            throw BrandAssetCheckError.missingBundledVectorLockup
        }
        guard let bundledLockup = EstroboBrandAssets.loadLockup(in: appBundle) else {
            throw BrandAssetCheckError.unreadableBundledLockup
        }
        expect(
            bundledLockup.representations.contains { $0 is NSPDFImageRep },
            "The built app must resolve the complete vector lockup"
        )

        guard
            let bundledVectorURL = appBundle.url(
                forResource: "EstroboMark",
                withExtension: "pdf",
                subdirectory: EstroboBrandAssets.resourceSubdirectory
            ),
            FileManager.default.fileExists(atPath: bundledVectorURL.path)
        else {
            throw BrandAssetCheckError.missingBundledVectorMark
        }
        guard let bundledImage = EstroboBrandAssets.loadMark(in: appBundle) else {
            throw BrandAssetCheckError.unreadableBundledMark
        }
        expect(
            bundledImage.representations.contains { $0 is NSPDFImageRep },
            "The built app must resolve the vector mark before the PNG fallback"
        )

        print("Estrobo vector lockup, mark fallback, and bundled brand assets verified")
    }

    private static func fileName(
        for resource: EstroboBrandAssets.ResourceDescriptor
    ) -> String {
        "\(resource.name).\(resource.fileExtension)"
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String
    ) {
        guard condition() else { preconditionFailure(message()) }
    }
}

private enum BrandAssetCheckError: Error {
    case missingVectorLockup
    case missingVectorMark
    case missingRasterFallback
    case invalidRasterFallback
    case invalidAppBundle
    case missingBundledVectorLockup
    case unreadableBundledLockup
    case missingBundledVectorMark
    case unreadableBundledMark
}
