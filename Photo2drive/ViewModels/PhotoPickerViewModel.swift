//
//  PhotoPickerViewModel.swift
//  Photo2drive
//

import Foundation
import PhotosUI
import SwiftUI

/// ViewModel for handling photo selection from the photo library.
@MainActor
@Observable
final class PhotoPickerViewModel {
    /// Selected photo picker items.
    var selectedItems: [PhotosPickerItem] = []

    /// Loaded photo items with image data.
    var photoItems: [PhotoItem] = []

    /// Whether photos are currently being loaded.
    var isLoading = false

    /// Error message if loading fails.
    var errorMessage: String?

    /// Loads image data from selected PhotosPickerItems.
    func loadPhotos() async {
        guard !selectedItems.isEmpty else {
            photoItems = []
            return
        }

        isLoading = true
        errorMessage = nil

        var loadedItems: [PhotoItem] = []

        for item in selectedItems {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let fileName = generateFileName(for: item)
                    let thumbnail = createThumbnail(from: data)

                    let photoItem = PhotoItem(
                        imageData: data,
                        thumbnail: thumbnail,
                        fileName: fileName,
                        creationDate: Date()
                    )
                    loadedItems.append(photoItem)
                }
            } catch {
                // 個別のエラーはスキップして続行
                continue
            }
        }

        photoItems = loadedItems
        isLoading = false
    }

    /// Clears all selected photos.
    func clearSelection() {
        selectedItems = []
        photoItems = []
    }

    /// Generates a filename for the photo.
    private func generateFileName(for item: PhotosPickerItem) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let uuid = UUID().uuidString.prefix(8)
        return "IMG_\(timestamp)_\(uuid).jpg"
    }

    /// Creates a thumbnail image from data.
    private func createThumbnail(from data: Data) -> Image? {
        guard let uiImage = UIImage(data: data) else {
            return nil
        }

        let thumbnailSize = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let thumbnailUIImage = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }

        return Image(uiImage: thumbnailUIImage)
    }
}
