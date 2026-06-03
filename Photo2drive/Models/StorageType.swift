//
//  StorageType.swift
//  Photo2drive
//

import Foundation

/// Represents the type of cloud storage service.
enum StorageType: String, Codable, CaseIterable, Identifiable {
    case googleDrive
    case box
    case dropbox

    var id: String { rawValue }

    /// Display name for the storage type.
    var displayName: String {
        switch self {
        case .googleDrive:
            return "Google Drive"
        case .box:
            return "Box"
        case .dropbox:
            return "Dropbox"
        }
    }

    /// SF Symbol icon name for the storage type.
    var iconName: String {
        switch self {
        case .googleDrive:
            return "g.circle.fill"
        case .box:
            return "shippingbox.fill"
        case .dropbox:
            return "drop.fill"
        }
    }

    /// Root folder ID for the storage type.
    var rootFolderId: String {
        switch self {
        case .googleDrive:
            return "root"
        case .box:
            return "0"
        case .dropbox:
            return ""
        }
    }
}
