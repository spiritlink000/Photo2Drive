//
//  CloudFolder.swift
//  Photo2drive
//

import Foundation

/// Represents a folder in a cloud storage service.
struct CloudFolder: Identifiable, Sendable, Hashable, Codable {
    let id: String
    let name: String
    let parentId: String?
    let isShared: Bool
    let storageType: StorageType

    init(id: String, name: String, parentId: String? = nil, isShared: Bool = false, storageType: StorageType) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.isShared = isShared
        self.storageType = storageType
    }
}

extension CloudFolder {
    /// Root folder for Google Drive.
    static let googleDriveRoot = CloudFolder(
        id: "root",
        name: "My Drive",
        parentId: nil,
        isShared: false,
        storageType: .googleDrive
    )

    /// Shared with me section for Google Drive.
    static let googleDriveSharedWithMe = CloudFolder(
        id: "sharedWithMe",
        name: "Shared with me",
        parentId: nil,
        isShared: true,
        storageType: .googleDrive
    )

    /// Root folder for Box.
    static let boxRoot = CloudFolder(
        id: "0",
        name: "All Files",
        parentId: nil,
        isShared: false,
        storageType: .box
    )

    /// Root folder for Dropbox.
    static let dropboxRoot = CloudFolder(
        id: "",
        name: "Dropbox",
        parentId: nil,
        isShared: false,
        storageType: .dropbox
    )

    /// Returns the root folder for a given storage type.
    static func root(for storageType: StorageType) -> CloudFolder {
        switch storageType {
        case .googleDrive:
            return .googleDriveRoot
        case .box:
            return .boxRoot
        case .dropbox:
            return .dropboxRoot
        }
    }
}
