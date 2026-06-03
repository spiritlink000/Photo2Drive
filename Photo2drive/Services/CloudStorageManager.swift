//
//  CloudStorageManager.swift
//  Photo2drive
//

import Foundation
import UIKit

/// Manages all cloud storage services.
@MainActor
@Observable
final class CloudStorageManager {
    /// Singleton instance.
    static let shared = CloudStorageManager()

    /// Google Drive auth service.
    let googleAuthService = GoogleAuthService()

    /// Box auth service.
    let boxAuthService = BoxAuthService()

    /// Dropbox auth service.
    let dropboxAuthService = DropboxAuthService()

    /// Google Drive file service.
    let googleDriveService = GoogleDriveService()

    /// Box file service.
    let boxStorageService = BoxStorageService()

    /// Dropbox file service.
    let dropboxStorageService = DropboxStorageService()

    private init() {}

    /// Returns whether the user is authenticated for the given storage type.
    func isAuthenticated(for storageType: StorageType) -> Bool {
        switch storageType {
        case .googleDrive:
            return googleAuthService.isSignedIn
        case .box:
            return boxAuthService.isSignedIn
        case .dropbox:
            return dropboxAuthService.isSignedIn
        }
    }

    /// Returns the user's display name for the given storage type.
    func userName(for storageType: StorageType) -> String? {
        switch storageType {
        case .googleDrive:
            return googleAuthService.userName
        case .box:
            return boxAuthService.userName
        case .dropbox:
            return dropboxAuthService.userName
        }
    }

    /// Returns the list of authenticated storage types.
    var authenticatedStorageTypes: [StorageType] {
        StorageType.allCases.filter { isAuthenticated(for: $0) }
    }

    /// Signs in to the specified storage.
    func signIn(to storageType: StorageType, from viewController: UIViewController) async throws {
        switch storageType {
        case .googleDrive:
            try await googleAuthService.signIn(presentingViewController: viewController)
        case .box:
            try await boxAuthService.signIn(from: viewController)
        case .dropbox:
            try await dropboxAuthService.signIn(from: viewController)
        }
    }

    /// Signs out from the specified storage.
    func signOut(from storageType: StorageType) {
        switch storageType {
        case .googleDrive:
            googleAuthService.signOut()
        case .box:
            boxAuthService.signOut()
        case .dropbox:
            dropboxAuthService.signOut()
        }
    }

    /// Gets access token for the specified storage.
    func getAccessToken(for storageType: StorageType) async throws -> String {
        switch storageType {
        case .googleDrive:
            return try await googleAuthService.getAccessToken()
        case .box:
            return try await boxAuthService.getAccessToken()
        case .dropbox:
            return try await dropboxAuthService.getAccessToken()
        }
    }

    /// Lists folders for the specified storage.
    func listFolders(in parentId: String, storageType: StorageType) async throws -> [CloudFolder] {
        let accessToken = try await getAccessToken(for: storageType)

        switch storageType {
        case .googleDrive:
            let folders = try await googleDriveService.listFolders(in: parentId, accessToken: accessToken)
            return folders.map { folder in
                CloudFolder(
                    id: folder.id,
                    name: folder.name,
                    parentId: folder.parentId,
                    isShared: folder.isShared,
                    storageType: .googleDrive
                )
            }
        case .box:
            return try await boxStorageService.listFolders(in: parentId, accessToken: accessToken)
        case .dropbox:
            return try await dropboxStorageService.listFolders(in: parentId, accessToken: accessToken)
        }
    }

    /// Lists shared folders for the specified storage.
    func listSharedFolders(storageType: StorageType) async throws -> [CloudFolder] {
        let accessToken = try await getAccessToken(for: storageType)

        switch storageType {
        case .googleDrive:
            let folders = try await googleDriveService.listSharedFolders(accessToken: accessToken)
            return folders.map { folder in
                CloudFolder(
                    id: folder.id,
                    name: folder.name,
                    parentId: folder.parentId,
                    isShared: true,
                    storageType: .googleDrive
                )
            }
        case .box:
            return try await boxStorageService.listSharedFolders(accessToken: accessToken)
        case .dropbox:
            return try await dropboxStorageService.listSharedFolders(accessToken: accessToken)
        }
    }

    /// Gets folder metadata for the specified storage.
    func getFolderMetadata(folderId: String, storageType: StorageType) async throws -> (folder: CloudFolder, parentId: String?)? {
        let accessToken = try await getAccessToken(for: storageType)

        switch storageType {
        case .googleDrive:
            if let result = try await googleDriveService.getFolderMetadata(folderId: folderId, accessToken: accessToken) {
                let cloudFolder = CloudFolder(
                    id: result.folder.id,
                    name: result.folder.name,
                    parentId: result.parentId,
                    isShared: result.folder.isShared,
                    storageType: .googleDrive
                )
                return (cloudFolder, result.parentId)
            }
            return nil
        case .box:
            return try await boxStorageService.getFolderMetadata(folderId: folderId, accessToken: accessToken)
        case .dropbox:
            return try await dropboxStorageService.getFolderMetadata(folderId: folderId, accessToken: accessToken)
        }
    }

    /// Gets parent folder for the specified storage.
    func getParentFolder(parentId: String, storageType: StorageType) async throws -> CloudFolder? {
        let accessToken = try await getAccessToken(for: storageType)

        switch storageType {
        case .googleDrive:
            if let folder = try await googleDriveService.getParentFolder(parentId: parentId, accessToken: accessToken) {
                return CloudFolder(
                    id: folder.id,
                    name: folder.name,
                    parentId: folder.parentId,
                    isShared: folder.isShared,
                    storageType: .googleDrive
                )
            }
            return nil
        case .box:
            return try await boxStorageService.getParentFolder(parentId: parentId, accessToken: accessToken)
        case .dropbox:
            return try await dropboxStorageService.getParentFolder(parentId: parentId, accessToken: accessToken)
        }
    }

    /// Uploads a file to the specified storage.
    func uploadFile(
        data: Data,
        fileName: String,
        mimeType: String,
        folderId: String,
        storageType: StorageType
    ) async throws -> String {
        let accessToken = try await getAccessToken(for: storageType)

        switch storageType {
        case .googleDrive:
            return try await googleDriveService.uploadFile(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                folderId: folderId,
                accessToken: accessToken
            )
        case .box:
            return try await boxStorageService.uploadFile(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                folderId: folderId,
                accessToken: accessToken
            )
        case .dropbox:
            return try await dropboxStorageService.uploadFile(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                folderId: folderId,
                accessToken: accessToken
            )
        }
    }

    /// Handles URL callback.
    func handleURL(_ url: URL) -> Bool {
        // Google Sign-In
        if googleAuthService.handle(url) {
            return true
        }

        // Box
        if boxAuthService.handleURL(url) {
            return true
        }

        // Dropbox
        if dropboxAuthService.handleURL(url) {
            return true
        }

        return false
    }
}
