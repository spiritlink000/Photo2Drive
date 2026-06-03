//
//  SettingsService.swift
//  Photo2drive
//

import Foundation

/// Service for persisting user settings.
enum SettingsService {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let lastFolderId = "lastSelectedFolderId"
        static let lastFolderName = "lastSelectedFolderName"
        static let lastFolderIsShared = "lastSelectedFolderIsShared"
        static let lastUploadQuality = "lastUploadQuality"
        static let lastStorageType = "lastStorageType"
        static let lastCloudFolder = "lastCloudFolder"
    }

    // MARK: - Legacy DriveFolder (互換性のため残す)

    /// Saves the selected folder to UserDefaults.
    static func saveSelectedFolder(_ folder: DriveFolder) {
        defaults.set(folder.id, forKey: Keys.lastFolderId)
        defaults.set(folder.name, forKey: Keys.lastFolderName)
        defaults.set(folder.isShared, forKey: Keys.lastFolderIsShared)
    }

    /// Loads the previously selected folder from UserDefaults.
    /// Returns nil if no folder was previously saved.
    static func loadSelectedFolder() -> DriveFolder? {
        guard let id = defaults.string(forKey: Keys.lastFolderId),
              let name = defaults.string(forKey: Keys.lastFolderName) else {
            return nil
        }

        let isShared = defaults.bool(forKey: Keys.lastFolderIsShared)
        return DriveFolder(id: id, name: name, parentId: nil, isShared: isShared)
    }

    // MARK: - CloudFolder

    /// Saves the selected cloud folder to UserDefaults.
    static func saveCloudFolder(_ folder: CloudFolder) {
        if let data = try? JSONEncoder().encode(folder) {
            defaults.set(data, forKey: Keys.lastCloudFolder)
        }
    }

    /// Loads the previously selected cloud folder from UserDefaults.
    /// Returns nil if no folder was previously saved.
    static func loadCloudFolder() -> CloudFolder? {
        guard let data = defaults.data(forKey: Keys.lastCloudFolder),
              let folder = try? JSONDecoder().decode(CloudFolder.self, from: data) else {
            return nil
        }
        return folder
    }

    // MARK: - Per-Storage CloudFolder

    /// Saves the selected cloud folder for a specific storage type.
    static func saveCloudFolder(_ folder: CloudFolder, for storageType: StorageType) {
        let key = "lastCloudFolder_\(storageType.rawValue)"
        if let data = try? JSONEncoder().encode(folder) {
            defaults.set(data, forKey: key)
        }
    }

    /// Loads the previously selected cloud folder for a specific storage type.
    static func loadCloudFolder(for storageType: StorageType) -> CloudFolder? {
        let key = "lastCloudFolder_\(storageType.rawValue)"
        guard let data = defaults.data(forKey: key),
              let folder = try? JSONDecoder().decode(CloudFolder.self, from: data) else {
            return nil
        }
        return folder
    }

    // MARK: - Upload Quality

    /// Saves the selected upload quality to UserDefaults.
    static func saveUploadQuality(_ quality: UploadQuality) {
        defaults.set(quality.rawValue, forKey: Keys.lastUploadQuality)
    }

    /// Loads the previously selected upload quality from UserDefaults.
    /// Returns .original if no quality was previously saved.
    static func loadUploadQuality() -> UploadQuality {
        guard let rawValue = defaults.string(forKey: Keys.lastUploadQuality),
              let quality = UploadQuality(rawValue: rawValue) else {
            return .original
        }
        return quality
    }
}
