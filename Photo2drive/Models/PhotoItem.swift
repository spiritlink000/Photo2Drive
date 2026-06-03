//
//  PhotoItem.swift
//  Photo2drive
//

import Foundation
import SwiftUI
import Photos

/// Represents a photo selected from the user's photo library.
struct PhotoItem: Identifiable, Sendable {
    let id: String
    let asset: PHAsset?
    let imageData: Data?
    let thumbnail: Image?
    let fileName: String
    let creationDate: Date?

    init(
        id: String = UUID().uuidString,
        asset: PHAsset? = nil,
        imageData: Data? = nil,
        thumbnail: Image? = nil,
        fileName: String,
        creationDate: Date? = nil
    ) {
        self.id = id
        self.asset = asset
        self.imageData = imageData
        self.thumbnail = thumbnail
        self.fileName = fileName
        self.creationDate = creationDate
    }
}

/// Represents the upload status of a photo.
enum UploadStatus: Sendable {
    case pending
    case uploading(progress: Double)
    case completed
    case failed(error: String)
}
