// ios/PetHomepage/DesignSystem/ImageDownscaler.swift
import UIKit

/// Shared downscale → JPEG step used by every photo picker path (library + camera), so the
/// behaviour is identical regardless of source.
enum ImageDownscaler {
    static func scaledJPEG(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        // Work in pixels (scale = 1) so maxDimension is a pixel cap regardless of screen scale.
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        let targetSize: CGSize
        if longest > maxDimension {
            let ratio = maxDimension / longest
            targetSize = CGSize(width: (pixelSize.width * ratio).rounded(),
                                height: (pixelSize.height * ratio).rounded())
        } else {
            targetSize = pixelSize
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize,
                                               format: {
                                                   let f = UIGraphicsImageRendererFormat()
                                                   f.scale = 1
                                                   return f
                                               }())
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        return scaled.jpegData(compressionQuality: quality)
    }
}
