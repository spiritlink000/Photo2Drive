//
//  GoogleDriveService.swift
//  Photo2drive
//

import Foundation

/// Error types for Google Drive operations.
enum GoogleDriveError: LocalizedError {
    case invalidResponse
    case uploadFailed(String)
    case listFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Google Drive API"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .listFailed(let message):
            return "Failed to list folders: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

/// Response structure for Google Drive files.list API.
private struct FilesListResponse: Decodable {
    let files: [FileResource]?
    let nextPageToken: String?
}

/// Response structure for Google Drive file resource.
private struct FileResource: Decodable {
    let id: String
    let name: String
    let parents: [String]?
}

/// Response structure for folder metadata.
private struct FolderMetadata: Decodable {
    let id: String
    let name: String
    let parents: [String]?
}

/// Service for interacting with Google Drive API.
actor GoogleDriveService {
    private let baseURL = "https://www.googleapis.com/drive/v3"
    private let uploadURL = "https://www.googleapis.com/upload/drive/v3"

    /// URLSession configured for uploads.
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    /// Lists folders in the specified parent folder.
    /// - Parameters:
    ///   - parentId: Parent folder ID (use "root" for root folder).
    ///   - accessToken: Valid access token.
    /// - Returns: Array of DriveFolder objects.
    func listFolders(in parentId: String, accessToken: String) async throws -> [DriveFolder] {
        let query = "'\(parentId)' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        guard let url = URL(string: "\(baseURL)/files?q=\(encodedQuery)&fields=files(id,name,parents)") else {
            throw GoogleDriveError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleDriveError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleDriveError.listFailed("Status: \(httpResponse.statusCode), \(errorMessage)")
            }

            let listResponse = try JSONDecoder().decode(FilesListResponse.self, from: data)
            let folders = listResponse.files?.map { file in
                DriveFolder(id: file.id, name: file.name, parentId: file.parents?.first)
            } ?? []

            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            throw GoogleDriveError.networkError(error.localizedDescription)
        }
    }

    /// Lists shared folders (folders shared with the user).
    /// - Parameter accessToken: Valid access token.
    /// - Returns: Array of shared DriveFolder objects.
    func listSharedFolders(accessToken: String) async throws -> [DriveFolder] {
        // 共有されているフォルダを取得（自分がオーナーでないフォルダ）
        let query = "mimeType='application/vnd.google-apps.folder' and sharedWithMe=true and trashed=false"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        guard let url = URL(string: "\(baseURL)/files?q=\(encodedQuery)&fields=files(id,name,parents)") else {
            throw GoogleDriveError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleDriveError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleDriveError.listFailed("Status: \(httpResponse.statusCode), \(errorMessage)")
            }

            let listResponse = try JSONDecoder().decode(FilesListResponse.self, from: data)
            let folders = listResponse.files?.map { file in
                DriveFolder(id: file.id, name: file.name, parentId: file.parents?.first, isShared: true)
            } ?? []

            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            throw GoogleDriveError.networkError(error.localizedDescription)
        }
    }

    /// Gets folder metadata including parent information.
    /// - Parameters:
    ///   - folderId: Folder ID to get metadata for.
    ///   - accessToken: Valid access token.
    /// - Returns: DriveFolder with parent information, or nil if not found.
    func getFolderMetadata(folderId: String, accessToken: String) async throws -> (folder: DriveFolder, parentId: String?)? {
        guard folderId != "root" && folderId != "sharedWithMe" else {
            return nil
        }

        guard let url = URL(string: "\(baseURL)/files/\(folderId)?fields=id,name,parents&supportsAllDrives=true") else {
            throw GoogleDriveError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleDriveError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                return nil
            }

            let metadata = try JSONDecoder().decode(FolderMetadata.self, from: data)
            let folder = DriveFolder(id: metadata.id, name: metadata.name, parentId: metadata.parents?.first)
            return (folder, metadata.parents?.first)
        } catch {
            return nil
        }
    }

    /// Gets parent folder information.
    /// - Parameters:
    ///   - parentId: Parent folder ID.
    ///   - accessToken: Valid access token.
    /// - Returns: DriveFolder representing the parent.
    func getParentFolder(parentId: String, accessToken: String) async throws -> DriveFolder? {
        if parentId == "root" {
            return .root
        }

        guard let url = URL(string: "\(baseURL)/files/\(parentId)?fields=id,name,parents&supportsAllDrives=true") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let metadata = try JSONDecoder().decode(FolderMetadata.self, from: data)
            return DriveFolder(id: metadata.id, name: metadata.name, parentId: metadata.parents?.first)
        } catch {
            return nil
        }
    }

    /// Lists subfolders of a shared folder.
    /// - Parameters:
    ///   - parentId: Parent folder ID.
    ///   - accessToken: Valid access token.
    /// - Returns: Array of DriveFolder objects.
    func listSharedSubfolders(in parentId: String, accessToken: String) async throws -> [DriveFolder] {
        let query = "'\(parentId)' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        // 共有ドライブのファイルも含める
        guard let url = URL(string: "\(baseURL)/files?q=\(encodedQuery)&fields=files(id,name,parents)&supportsAllDrives=true&includeItemsFromAllDrives=true") else {
            throw GoogleDriveError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleDriveError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GoogleDriveError.listFailed("Status: \(httpResponse.statusCode), \(errorMessage)")
            }

            let listResponse = try JSONDecoder().decode(FilesListResponse.self, from: data)
            let folders = listResponse.files?.map { file in
                DriveFolder(id: file.id, name: file.name, parentId: file.parents?.first, isShared: true)
            } ?? []

            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            throw GoogleDriveError.networkError(error.localizedDescription)
        }
    }

    /// Uploads a file to Google Drive using resumable upload.
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
    ) async throws -> String {
        // Step 1: Resumable uploadセッションを開始
        let uploadUrl = try await initiateResumableUpload(
            fileName: fileName,
            mimeType: mimeType,
            folderId: folderId,
            fileSize: data.count,
            accessToken: accessToken
        )

        // Step 2: ファイルデータをアップロード
        return try await uploadData(data: data, to: uploadUrl, mimeType: mimeType)
    }

    /// Initiates a resumable upload session.
    private func initiateResumableUpload(
        fileName: String,
        mimeType: String,
        folderId: String,
        fileSize: Int,
        accessToken: String
    ) async throws -> URL {
        // 共有フォルダへのアップロードをサポート
        guard let url = URL(string: "\(uploadURL)/files?uploadType=resumable&supportsAllDrives=true") else {
            throw GoogleDriveError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.timeoutInterval = 30

        let metadata: [String: Any] = [
            "name": fileName,
            "parents": [folderId]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.invalidResponse
        }

        guard httpResponse.statusCode == 200,
              let locationHeader = httpResponse.value(forHTTPHeaderField: "Location"),
              let uploadUrl = URL(string: locationHeader) else {
            throw GoogleDriveError.uploadFailed("Failed to initiate upload: status \(httpResponse.statusCode)")
        }

        return uploadUrl
    }

    /// Uploads the actual file data to the resumable upload URL.
    private func uploadData(data: Data, to uploadUrl: URL, mimeType: String) async throws -> String {
        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 300
        request.httpBody = data

        let (responseData, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.invalidResponse
        }

        // 200 OK または 201 Created を成功とみなす
        guard (200...201).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw GoogleDriveError.uploadFailed("Status: \(httpResponse.statusCode), \(errorMessage)")
        }

        let fileResponse = try JSONDecoder().decode(FileResource.self, from: responseData)
        return fileResponse.id
    }
}
