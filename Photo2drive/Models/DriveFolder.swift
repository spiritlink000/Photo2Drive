//
//  DriveFolder.swift
//  Photo2drive
//

import Foundation

/// Represents a folder in Google Drive.
struct DriveFolder: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let parentId: String?
    let isShared: Bool

    init(id: String, name: String, parentId: String? = nil, isShared: Bool = false) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.isShared = isShared
    }
}

extension DriveFolder {
    /// Root folder constant representing "My Drive".
    static let root = DriveFolder(id: "root", name: "My Drive", parentId: nil)

    /// Special folder representing "Shared with me" section.
    static let sharedWithMe = DriveFolder(id: "sharedWithMe", name: "Shared with me", parentId: nil, isShared: true)
}
