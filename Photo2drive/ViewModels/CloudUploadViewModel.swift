//
//  CloudUploadViewModel.swift
//  Photo2drive
//

import Foundation

/// Represents the upload state of a single photo for cloud storage.
struct CloudUploadItem: Identifiable {
    let id: String
    let photoItem: PhotoItem
    var status: UploadStatus
}

/// ViewModel for managing photo uploads to any cloud storage.
@MainActor
@Observable
final class CloudUploadViewModel {
    /// Items to be uploaded with their status.
    var uploadItems: [CloudUploadItem] = []

    /// Selected upload quality.
    var selectedQuality: UploadQuality = .original {
        didSet {
            SettingsService.saveUploadQuality(selectedQuality)
        }
    }

    /// Selected destination folder.
    var selectedFolder: CloudFolder? {
        didSet {
            if let folder = selectedFolder {
                // 全体用とストレージ別の両方に保存
                SettingsService.saveCloudFolder(folder)
                SettingsService.saveCloudFolder(folder, for: folder.storageType)
            }
        }
    }

    init() {
        // 保存された設定を読み込む
        if let savedFolder = SettingsService.loadCloudFolder() {
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

    /// Sets up upload items from photo items.
    func setupUploadItems(from photoItems: [PhotoItem]) {
        uploadItems = photoItems.map { photo in
            CloudUploadItem(id: photo.id, photoItem: photo, status: .pending)
        }
    }

    /// Starts uploading all pending items.
    func startUpload(storageManager: CloudStorageManager) async {
        guard let folder = selectedFolder else { return }

        isUploading = true

        for index in uploadItems.indices {
            guard case .pending = uploadItems[index].status else { continue }

            uploadItems[index].status = .uploading(progress: 0)

            do {
                let photoItem = uploadItems[index].photoItem

                guard let imageData = photoItem.imageData else {
                    uploadItems[index].status = .failed(error: "No image data")
                    continue
                }

                // 画質設定に応じて圧縮
                let dataToUpload = ImageCompressor.compress(imageData, quality: selectedQuality)

                print("[Upload] Starting upload: \(photoItem.fileName), size: \(dataToUpload.count) bytes, storage: \(folder.storageType.displayName)")
                uploadItems[index].status = .uploading(progress: 0.5)

                let fileId = try await storageManager.uploadFile(
                    data: dataToUpload,
                    fileName: photoItem.fileName,
                    mimeType: "image/jpeg",
                    folderId: folder.id,
                    storageType: folder.storageType
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
    func retryFailed(storageManager: CloudStorageManager) async {
        // 失敗したアイテムを保留状態に戻す
        for index in uploadItems.indices {
            if case .failed = uploadItems[index].status {
                uploadItems[index].status = .pending
            }
        }

        await startUpload(storageManager: storageManager)
    }

    /// Clears all upload items.
    func clear() {
        uploadItems = []
        isUploading = false
    }
}
