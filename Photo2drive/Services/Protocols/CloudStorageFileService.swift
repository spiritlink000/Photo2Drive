//
//  CloudStorageFileService.swift
//  Photo2drive
//

import Foundation

/// Protocol for cloud storage file operations.
protocol CloudStorageFileService: Sendable {
    /// The type of storage this service handles.
    var storageType: StorageType { get }

    /// Lists folders in the specified parent folder.
    /// - Parameters:
    ///   - parentId: Parent folder ID.
    ///   - accessToken: Valid access token.
    /// - Returns: Array of CloudFolder objects.
    func listFolders(in parentId: String, accessToken: String) async throws -> [CloudFolder]

    /// Lists shared folders.
    /// - Parameter accessToken: Valid access token.
    /// - Returns: Array of shared CloudFolder objects.
    func listSharedFolders(accessToken: String) async throws -> [CloudFolder]

    /// Gets folder metadata including parent information.
    /// - Parameters:
    ///   - folderId: Folder ID.
    ///   - accessToken: Valid access token.
    /// - Returns: Tuple of folder and parent ID, or nil if not found.
    func getFolderMetadata(folderId: String, accessToken: String) async throws -> (folder: CloudFolder, parentId: String?)?

    /// Gets parent folder information.
    /// - Parameters:
    ///   - parentId: Parent folder ID.
    ///   - accessToken: Valid access token.
    /// - Returns: CloudFolder representing the parent.
    func getParentFolder(parentId: String, accessToken: String) async throws -> CloudFolder?

    /// Uploads a file to the storage.
    /// - Parameters:
    ///   - data: File data to upload.
    ///   - fileName: Name for the uploaded file.
    ///   - mimeType: MIME type of the file.
    ///   - folderId: Destination folder ID.
    ///   - accessToken: Valid access token.
    /// - Returns: ID of the uploaded file.
    func uploadFile(
        data: Data,
        fileName: String,
        mimeType: String,
        folderId: String,
        accessToken: String
    ) async throws -> String
}
