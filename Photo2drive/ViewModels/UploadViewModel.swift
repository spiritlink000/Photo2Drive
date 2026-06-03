//
//  UploadViewModel.swift
//  Photo2drive
//

import Foundation

/// Represents the upload state of a single photo.
struct UploadItem: Identifiable {
    let id: String
    let photoItem: PhotoItem
    var status: UploadStatus
}

/// ViewModel for managing photo uploads to Google Drive.
@MainActor
@Observable
final class UploadViewModel {
    /// Items to be uploaded with their status.
    var uploadItems: [UploadItem] = []

    /// Selected upload quality.
    var selectedQuality: UploadQuality = .original {
        didSet {
            SettingsService.saveUploadQuality(selectedQuality)
        }
    }

    /// Selected destination folder.
    var selectedFolder: DriveFolder = .root {
        didSet {
            SettingsService.saveSelectedFolder(selectedFolder)
        }
    }

    init() {
        // 保存された設定を読み込む
        if let savedFolder = SettingsService.loadSelectedFolder() {
            selectedFolder = savedFolder
        }
        selectedQuality = SettingsService.loadUploadQuality()
    }

    /// Overall upload progress (0.0 to 1.0).
    var overallProgress: Double {
        guard !uploadItems.isEmpty else { return 0 }

        let completedCount = uploadItems.filter {
            if case .completed = $0.status { return true }
            return false
        }.count

        return Double(completedCount) / Double(uploadItems.count)
    }

    /// Whether upload is in progress.
    var isUploading = false

    /// Whether all uploads are completed.
    var isCompleted: Bool {
        !uploadItems.isEmpty && uploadItems.allSatisfy {
            if case .completed = $0.status { return true }
            return false
        }
    }

    /// Number of failed uploads.
    var failedCount: Int {
        uploadItems.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    /// Number of completed uploads.
    var completedCount: Int {
        uploadItems.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    private let driveService = GoogleDriveService()

    /// Sets up upload items from photo items.
    func setupUploadItems(from photoItems: [PhotoItem]) {
        uploadItems = photoItems.map { photo in
            UploadItem(id: photo.id, photoItem: photo, status: .pending)
        }
    }

    /// Starts uploading all pending items.
    func startUpload(authService: GoogleAuthService) async {
        isUploading = true

        for index in uploadItems.indices {
            guard case .pending = uploadItems[index].status else { continue }

            uploadItems[index].status = .uploading(progress: 0)

            do {
                let accessToken = try await authService.getAccessToken()
                let photoItem = uploadItems[index].photoItem

                guard let imageData = photoItem.imageData else {
                    uploadItems[index].status = .failed(error: "No image data")
                    continue
                }

                // 画質設定に応じて圧縮
                let dataToUpload = ImageCompressor.compress(imageData, quality: selectedQuality)

                print("[Upload] Starting upload: \(photoItem.fileName), size: \(dataToUpload.count) bytes")
                uploadItems[index].status = .uploading(progress: 0.5)

                let fileId = try await driveService.uploadFile(
                    data: dataToUpload,
                    fileName: photoItem.fileName,
                    mimeType: "image/jpeg",
                    folderId: selectedFolder.id,
                    accessToken: accessToken
                )

                print("[Upload] Success: \(photoItem.fileName), fileId: \(fileId)")
                uploadItems[index].status = .completed
            } catch {
                print("[Upload] Error: \(error)")
                uploadItems[index].status = .failed(error: error.localizedDescription)
            }
        }

        isUploading = false
    }

    /// Retries failed uploads.
    func retryFailed(authService: GoogleAuthService) async {
        // 失敗したアイテムを保留状態に戻す
        for index in uploadItems.indices {
            if case .failed = uploadItems[index].status {
                uploadItems[index].status = .pending
            }
        }

        await startUpload(authService: authService)
    }

    /// Clears all upload items.
    func clear() {
        uploadItems = []
        isUploading = false
    }
}
