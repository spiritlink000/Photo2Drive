//
//  DropboxStorageService.swift
//  Photo2drive
//

import Foundation

/// Service for interacting with Dropbox API.
actor DropboxStorageService: CloudStorageFileService {
    let storageType: StorageType = .dropbox

    private let apiURL = "https://api.dropboxapi.com/2"
    private let contentURL = "https://content.dropboxapi.com/2"

    /// URLSession configured for uploads.
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    /// Lists folders in the specified path.
    func listFolders(in parentId: String, accessToken: String) async throws -> [CloudFolder] {
        let path = parentId.isEmpty ? "" : parentId

        guard let url = URL(string: "\(apiURL)/files/list_folder") else {
            throw CloudStorageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "path": path,
            "recursive": false,
            "include_mounted_folders": true,
            "include_non_downloadable_files": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudStorageError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw CloudStorageError.listFailed("Status: \(httpResponse.statusCode), \(errorMessage)")
            }

            let listResponse = try JSONDecoder().decode(DropboxListFolderResponse.self, from: data)
            let folders = listResponse.entries
                .filter { $0.tag == "folder" }
                .map { entry in
                    // Dropboxのパスから親パスを抽出
                    let parentPath = extractParentPath(from: entry.pathDisplay ?? entry.pathLower ?? "")
                    return CloudFolder(
                        id: entry.pathLower ?? entry.id,
                        name: entry.name,
                        parentId: parentPath,
                        isShared: false,
                        storageType: .dropbox
                    )
                }

            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch let error as CloudStorageError {
            throw error
        } catch {
            throw CloudStorageError.networkError(error.localizedDescription)
        }
    }

    /// Extracts parent path from a Dropbox path.
    private func extractParentPath(from path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count > 1 else { return "" }
        let parentComponents = components.dropLast()
        return "/" + parentComponents.joined(separator: "/")
    }

    /// Lists shared folders.
    func listSharedFolders(accessToken: String) async throws -> [CloudFolder] {
        guard let url = URL(string: "\(apiURL)/sharing/list_folders") else {
            throw CloudStorageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "limit": 100
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudStorageError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                return []
            }

            let listResponse = try JSONDecoder().decode(DropboxSharedFoldersResponse.self, from: data)
            let folders = listResponse.entries.map { entry in
                CloudFolder(
                    id: entry.pathLower ?? entry.sharedFolderId,
                    name: entry.name,
                    parentId: nil,
                    isShared: true,
                    storageType: .dropbox
                )
            }

            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            return []
        }
    }

    /// Gets folder metadata.
    func getFolderMetadata(folderId: String, accessToken: String) async throws -> (folder: CloudFolder, parentId: String?)? {
        guard !folderId.isEmpty else { return nil }

        guard let url = URL(string: "\(apiURL)/files/get_metadata") else {
            throw CloudStorageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "path": folderId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let metadata = try JSONDecoder().decode(DropboxFileMetadata.self, from: data)
            let parentPath = extractParentPath(from: metadata.pathDisplay ?? metadata.pathLower ?? "")

            let folder = CloudFolder(
                id: metadata.pathLower ?? metadata.id,
                name: metadata.name,
                parentId: parentPath,
                isShared: false,
                storageType: .dropbox
            )
            return (folder, parentPath)
        } catch {
            return nil
        }
    }

    /// Gets parent folder information.
    func getParentFolder(parentId: String, accessToken: String) async throws -> CloudFolder? {
        if parentId.isEmpty {
            return .dropboxRoot
        }

        guard let url = URL(string: "\(apiURL)/files/get_metadata") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "path": parentId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let metadata = try JSONDecoder().decode(DropboxFileMetadata.self, from: data)
            let parentPath = extractParentPath(from: metadata.pathDisplay ?? metadata.pathLower ?? "")

            return CloudFolder(
                id: metadata.pathLower ?? metadata.id,
                name: metadata.name,
                parentId: parentPath,
                isShared: false,
                storageType: .dropbox
            )
        } catch {
            return nil
        }
    }

    /// Uploads a file to Dropbox.
    func uploadFile(
        data: Data,
        fileName: String,
        mimeType: String,
        folderId: String,
        accessToken: String
    ) async throws -> String {
        let path = folderId.isEmpty ? "/\(fileName)" : "\(folderId)/\(fileName)"

        guard let url = URL(string: "\(contentURL)/files/upload") else {
            throw CloudStorageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        // Dropbox-API-Argヘッダーでメタデータを指定
        let args: [String: Any] = [
            "path": path,
            "mode": "add",
            "autorename": true,
            "mute": false,
            "strict_conflict": false
        ]

        let argsData = try JSONSerialization.data(withJSONObject: args)
        let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
        // Dropbox-API-ArgヘッダーはASCII文字のみ許可される。日本語などの非ASCII文字を含む
        // フォルダパスやファイル名はそのまま送るとリクエストが不正になるため、\uXXXX形式にエスケープする
        request.setValue(Self.asciiEscaped(argsString), forHTTPHeaderField: "Dropbox-API-Arg")

        request.httpBody = data

        let (responseData, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw CloudStorageError.uploadFailed("Status: \(httpResponse.statusCode), \(errorMessage)")
        }

        let uploadResponse = try JSONDecoder().decode(DropboxFileMetadata.self, from: responseData)
        return uploadResponse.id
    }

    /// Escapes non-ASCII characters in a string to `\uXXXX` form for safe use in HTTP headers.
    ///
    /// The `Dropbox-API-Arg` header only accepts ASCII characters, so any non-ASCII
    /// character (e.g. Japanese folder names) must be escaped before being sent.
    private static func asciiEscaped(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            if scalar.isASCII {
                result.unicodeScalars.append(scalar)
            } else {
                // UTF-16コードユニットごとに\uXXXX形式へ変換する(サロゲートペアにも対応)
                for unit in String(scalar).utf16 {
                    result += String(format: "\\u%04x", unit)
                }
            }
        }
        return result
    }
}

// MARK: - Response Models

private struct DropboxListFolderResponse: Decodable {
    let entries: [DropboxEntry]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case entries
        case hasMore = "has_more"
    }
}

private struct DropboxEntry: Decodable {
    let tag: String
    let id: String
    let name: String
    let pathLower: String?
    let pathDisplay: String?

    enum CodingKeys: String, CodingKey {
        case tag = ".tag"
        case id
        case name
        case pathLower = "path_lower"
        case pathDisplay = "path_display"
    }
}

private struct DropboxSharedFoldersResponse: Decodable {
    let entries: [DropboxSharedFolder]
}

private struct DropboxSharedFolder: Decodable {
    let sharedFolderId: String
    let name: String
    let pathLower: String?

    enum CodingKeys: String, CodingKey {
        case sharedFolderId = "shared_folder_id"
        case name
        case pathLower = "path_lower"
    }
}

private struct DropboxFileMetadata: Decodable {
    let id: String
    let name: String
    let pathLower: String?
    let pathDisplay: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case pathLower = "path_lower"
        case pathDisplay = "path_display"
    }
}
