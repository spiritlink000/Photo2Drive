//
//  BoxStorageService.swift
//  Photo2drive
//

import Foundation

/// Service for interacting with Box API.
actor BoxStorageService: CloudStorageFileService {
    let storageType: StorageType = .box

    private let baseURL = "https://api.box.com/2.0"
    private let uploadURL = "https://upload.box.com/api/2.0"

    /// URLSession configured for uploads.
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    /// Lists folders in the specified parent folder.
    func listFolders(in parentId: String, accessToken: String) async throws -> [CloudFolder] {
        let folderId = parentId.isEmpty ? "0" : parentId
        guard let url = URL(string: "\(baseURL)/folders/\(folderId)/items?fields=id,name,type,parent&limit=1000") else {
            throw CloudStorageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudStorageError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw CloudStorageError.listFailed("Status: \(httpResponse.statusCode), \(errorMessage)")
            }

            let listResponse = try JSONDecoder().decode(BoxItemsResponse.self, from: data)
            let folders = listResponse.entries
                .filter { $0.type == "folder" }
                .map { item in
                    CloudFolder(
                        id: item.id,
                        name: item.name,
                        parentId: item.parent?.id,
                        isShared: false,
                        storageType: .box
                    )
                }

            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch let error as CloudStorageError {
            throw error
        } catch {
            throw CloudStorageError.networkError(error.localizedDescription)
        }
    }

    /// Lists shared folders (collaborations).
    func listSharedFolders(accessToken: String) async throws -> [CloudFolder] {
        guard let url = URL(string: "\(baseURL)/collaborations?fields=item&status=accepted") else {
            throw CloudStorageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudStorageError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                // 共有フォルダがない場合は空配列を返す
                return []
            }

            let collabResponse = try JSONDecoder().decode(BoxCollaborationsResponse.self, from: data)
            let folders = collabResponse.entries
                .compactMap { $0.item }
                .filter { $0.type == "folder" }
                .map { item in
                    CloudFolder(
                        id: item.id,
                        name: item.name,
                        parentId: nil,
                        isShared: true,
                        storageType: .box
                    )
                }

            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            // エラーが発生しても空配列を返す
            return []
        }
    }

    /// Gets folder metadata.
    func getFolderMetadata(folderId: String, accessToken: String) async throws -> (folder: CloudFolder, parentId: String?)? {
        guard folderId != "0" else { return nil }

        guard let url = URL(string: "\(baseURL)/folders/\(folderId)?fields=id,name,parent") else {
            throw CloudStorageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let folderInfo = try JSONDecoder().decode(BoxFolderInfo.self, from: data)
            let folder = CloudFolder(
                id: folderInfo.id,
                name: folderInfo.name,
                parentId: folderInfo.parent?.id,
                isShared: false,
                storageType: .box
            )
            return (folder, folderInfo.parent?.id)
        } catch {
            return nil
        }
    }

    /// Gets parent folder information.
    func getParentFolder(parentId: String, accessToken: String) async throws -> CloudFolder? {
        if parentId == "0" {
            return .boxRoot
        }

        guard let url = URL(string: "\(baseURL)/folders/\(parentId)?fields=id,name,parent") else {
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

            let folderInfo = try JSONDecoder().decode(BoxFolderInfo.self, from: data)
            return CloudFolder(
                id: folderInfo.id,
                name: folderInfo.name,
                parentId: folderInfo.parent?.id,
                isShared: false,
                storageType: .box
            )
        } catch {
            return nil
        }
    }

    /// Uploads a file to Box.
    func uploadFile(
        data: Data,
        fileName: String,
        mimeType: String,
        folderId: String,
        accessToken: String
    ) async throws -> String {
        let targetFolderId = folderId.isEmpty ? "0" : folderId
        guard let url = URL(string: "\(uploadURL)/files/content") else {
            throw CloudStorageError.invalidResponse
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        // メタデータ部分
        let attributes: [String: Any] = [
            "name": fileName,
            "parent": ["id": targetFolderId]
        ]
        let attributesData = try JSONSerialization.data(withJSONObject: attributes)
        let attributesString = String(data: attributesData, encoding: .utf8) ?? "{}"

        // マルチパートボディを構築
        var body = Data()

        // attributes part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"attributes\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(attributesString)\r\n".data(using: .utf8)!)

        // file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // 終端
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidResponse
        }

        guard (200...201).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw CloudStorageError.uploadFailed("Status: \(httpResponse.statusCode), \(errorMessage)")
        }

        let uploadResponse = try JSONDecoder().decode(BoxUploadResponse.self, from: responseData)
        guard let fileId = uploadResponse.entries.first?.id else {
            throw CloudStorageError.uploadFailed("No file ID in response")
        }

        return fileId
    }
}

// MARK: - Response Models

private struct BoxItemsResponse: Decodable {
    let entries: [BoxItem]
}

private struct BoxItem: Decodable {
    let id: String
    let name: String
    let type: String
    let parent: BoxParentRef?
}

private struct BoxParentRef: Decodable {
    let id: String
}

private struct BoxFolderInfo: Decodable {
    let id: String
    let name: String
    let parent: BoxParentRef?
}

private struct BoxCollaborationsResponse: Decodable {
    let entries: [BoxCollaboration]
}

private struct BoxCollaboration: Decodable {
    let item: BoxItem?
}

private struct BoxUploadResponse: Decodable {
    let entries: [BoxFileEntry]
}

private struct BoxFileEntry: Decodable {
    let id: String
}
