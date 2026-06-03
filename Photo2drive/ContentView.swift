//
//  ContentView.swift
//  Photo2drive
//

import SwiftUI
import PhotosUI

/// Main content view of the application.
struct ContentView: View {
    @State private var storageManager = CloudStorageManager.shared
    @State private var photoPickerViewModel = PhotoPickerViewModel()
    @State private var uploadViewModel = CloudUploadViewModel()

    @State private var showingPhotoPicker = false
    @State private var showingFolderPicker = false
    @State private var showingUploadView = false
    @State private var showingStorageAccounts = false

    /// 認証済みのストレージがあるか
    private var hasAuthenticatedStorage: Bool {
        !storageManager.authenticatedStorageTypes.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if hasAuthenticatedStorage {
                    signedInView
                } else {
                    signedOutView
                }
            }
            .padding()
            .navigationTitle("Photo2Drive")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingStorageAccounts = true
                    } label: {
                        connectedStoragesView
                    }
                }
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $photoPickerViewModel.selectedItems,
                maxSelectionCount: 50,
                matching: .images
            )
            .onChange(of: photoPickerViewModel.selectedItems) {
                Task {
                    await photoPickerViewModel.loadPhotos()
                }
            }
            .sheet(isPresented: $showingFolderPicker) {
                CloudFolderPickerView(
                    selectedFolder: $uploadViewModel.selectedFolder,
                    storageManager: storageManager,
                    onDismiss: { showingFolderPicker = false }
                )
            }
            .sheet(isPresented: $showingStorageAccounts) {
                StorageAccountsView(storageManager: storageManager)
            }
            .fullScreenCover(isPresented: $showingUploadView) {
                CloudUploadView(
                    viewModel: uploadViewModel,
                    storageManager: storageManager,
                    onComplete: {
                        showingUploadView = false
                        photoPickerViewModel.clearSelection()
                        uploadViewModel.clear()
                    }
                )
            }
        }
    }

    // MARK: - Connected Storages View

    private var connectedStoragesView: some View {
        HStack(spacing: 4) {
            ForEach(StorageType.allCases) { storageType in
                if storageManager.isAuthenticated(for: storageType) {
                    Image(systemName: storageType.iconName)
                        .font(.caption)
                        .foregroundStyle(iconColor(for: storageType))
                }
            }

            if !hasAuthenticatedStorage {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundStyle(.blue)
            }
        }
    }

    private func iconColor(for storageType: StorageType) -> Color {
        switch storageType {
        case .googleDrive:
            return .green
        case .box:
            return .blue
        case .dropbox:
            return .blue
        }
    }

    // MARK: - Signed Out View

    private var signedOutView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Upload photos to\nCloud Storage")
                .font(.title)
                .multilineTextAlignment(.center)

            Text("Connect to Google Drive, Box, or Dropbox to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingStorageAccounts = true
            } label: {
                HStack {
                    Image(systemName: "link.circle")
                    Text("Connect Storage")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }

    // MARK: - Signed In View

    private var signedInView: some View {
        VStack(spacing: 16) {
            if !photoPickerViewModel.photoItems.isEmpty {
                selectedPhotosSection
            } else {
                emptyStateView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Select photos to upload")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                showingPhotoPicker = true
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("Select Photos")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }

    private var selectedPhotosSection: some View {
        VStack(spacing: 16) {
            // 写真グリッド
            PhotoGridView(photoItems: photoPickerViewModel.photoItems)
                .frame(maxHeight: 300)

            // 選択数表示
            HStack {
                Text("\(photoPickerViewModel.photoItems.count) photos selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Change") {
                    showingPhotoPicker = true
                }
                .font(.subheadline)
            }

            Divider()

            // フォルダ選択
            folderSelectionRow

            // 画質選択
            qualitySelectionRow

            Spacer()

            // アップロードボタン
            uploadButton
        }
    }

    private var folderSelectionRow: some View {
        Button {
            showingFolderPicker = true
        } label: {
            HStack {
                if let folder = uploadViewModel.selectedFolder {
                    Image(systemName: folder.storageType.iconName)
                        .foregroundStyle(iconColor(for: folder.storageType))
                } else {
                    Image(systemName: "folder")
                        .foregroundStyle(.blue)
                }

                Text("Destination")
                    .foregroundStyle(.primary)
                Spacer()

                if let folder = uploadViewModel.selectedFolder {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(folder.name)
                            .foregroundStyle(.secondary)
                        Text(folder.storageType.displayName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Select folder")
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var qualitySelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upload Quality")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Quality", selection: $uploadViewModel.selectedQuality) {
                ForEach(UploadQuality.allCases) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var uploadButton: some View {
        Button {
            uploadViewModel.setupUploadItems(from: photoPickerViewModel.photoItems)
            showingUploadView = true
        } label: {
            HStack {
                Image(systemName: "icloud.and.arrow.up")

                if let folder = uploadViewModel.selectedFolder {
                    Text("Upload to \(folder.storageType.displayName)")
                } else {
                    Text("Upload")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(uploadViewModel.selectedFolder == nil)
    }
}

#Preview {
    ContentView()
}
