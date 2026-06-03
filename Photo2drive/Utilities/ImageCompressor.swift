//
//  ImageCompressor.swift
//  Photo2drive
//

import Foundation
import UIKit

/// Utility for compressing images before upload.
enum ImageCompressor {

    /// Compresses image data according to the specified quality settings.
    /// - Parameters:
    ///   - imageData: Original image data.
    ///   - quality: Upload quality setting.
    /// - Returns: Compressed image data, or original if compression fails.
    static func compress(_ imageData: Data, quality: UploadQuality) -> Data {
        guard quality == .compressed else {
            return imageData
        }

        guard let image = UIImage(data: imageData) else {
            return imageData
        }

        let resizedImage = resizeIfNeeded(image, maxDimension: quality.maxDimension)
        guard let compressedData = resizedImage.jpegData(compressionQuality: quality.compressionQuality) else {
            return imageData
        }

        return compressedData
    }

    /// Resizes image if it exceeds the maximum dimension.
    /// - Parameters:
    ///   - image: Original image.
    ///   - maxDimension: Maximum width or height.
    /// - Returns: Resized image or original if no resizing needed.
    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat?) -> UIImage {
        guard let maxDimension = maxDimension else {
            return image
        }

        let size = image.size
        let maxCurrentDimension = max(size.width, size.height)

        guard maxCurrentDimension > maxDimension else {
            return image
        }

        let scale = maxDimension / maxCurrentDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage
    }
}
