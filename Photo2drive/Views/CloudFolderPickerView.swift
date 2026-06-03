//
//  CloudFolderPickerView.swift
//  Photo2drive
//

import SwiftUI

/// View for selecting a folder from any cloud storage.
struct CloudFolderPickerView: View {
    @Binding var selectedFolder: CloudFolder?
    let storageManager: CloudStorageManager
    let onDismiss: () -> Void

    @State private var selectedStorageType: StorageType
    @State private var folders: [CloudFolder] = []
    @State private var sharedFolders: [CloudFolder] = []
    @State private var currentFolder: CloudFolder
    @State private var navigationPath: [CloudFolder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isInSharedSection = false
    @State private var parentFolder: CloudFolder?

    init(selectedFolder: Binding<CloudFolder?>, storageManager: CloudStorageManager, onDismiss: @escaping () -> Void) {
        self._selectedFolder = selectedFolder
        self.storageManager = storageManager
        self.onDismiss = onDismiss

        // 選択済みフォルダがある場合はそのストレージとフォルダから開始
        if let folder = selectedFolder.wrappedValue {
            self._selectedStorageType = State(initialValue: folder.storageType)
            self._currentFolder = State(initialValue: folder)
            self._isInSharedSection = State(initialValue: folder.isShared)
        } else {
            // デフォルトは認証済みの最初のストレージ
            let defaultType = storageManager.authenticatedStorageTypes.first ?? .googleDrive
            self._selectedStorageType = State(initialValue: defaultType)
            self._currentFolder = State(initialValue: .root(for: defaultType))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ストレージタブ
                storageTabBar

                Divider()

                // フォルダ一覧
                if !storageManager.isAuthenticated(for: selectedStorageType) {
                    notAuthenticatedView
                } else if isLoading {
                    ProgressView("Loading folders...")
                        .frame(maxHeight: .infinity)
                } else if let error = errorMessage {
                    errorView(message: error)
                } else {
                    folderListView
                }
            }
            .navigationTitle("Select Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        selectedFolder = currentFolder
                        onDismiss()
                    }
                    .disabled(!canSelectCurrentFolder)
                }
            }
        }
        .task {
            if storageManager.isAuthenticated(for: selectedStorageType) {
                await loadFolders()
            }
        }
    }

    private var canSelectCurrentFolder: Bool {
        // 認証されていない場合は選択不可
        guard storageManager.isAuthenticated(for: selectedStorageType) else { return false }

        // Google Driveの「Shared with me」セクション自体は選択不可
        if selectedStorageType == .googleDrive && currentFolder.id == "sharedWithMe" {
            return false
        }

        return true
    }

    private var storageTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(StorageType.allCases) { storageType in
                    storageTab(for: storageType)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func storageTab(for storageType: StorageType) -> some View {
        Button {
            if selectedStorageType != storageType {
                selectedStorageType = storageType
                navigationPath = []
                parentFolder = nil
                folders = []
                sharedFolders = []

                // 保存されたフォルダがあればそれを使用、なければルート
                if let savedFolder = SettingsService.loadCloudFolder(for: storageType) {
                    currentFolder = savedFolder
                    isInSharedSection = savedFolder.isShared
                } else {
                    currentFolder = .root(for: storageType)
                    isInSharedSection = false
                }

                if storageManager.isAuthenticated(for: storageType) {
                    Task {
                        await loadFolders()
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: storageType.iconName)
                Text(storageType.displayName)
                    .font(.subheadline)

                if storageManager.isAuthenticated(for: storageType) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedStorageType == storageType ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(selectedStorageType == storageType ? .white : .primary)
            .clipShape(Capsule())
        }
    }

    private var notAuthenticatedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Not signed in to \(selectedStorageType.displayName)")
                .font(.headline)
            Text("Please sign in from Storage Accounts")
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var folderListView: some View {
        List {
            // 現在のフォルダを選択するオプション
            if canSelectCurrentFolder {
                Section {
                    HStack {
                        Image(systemName: currentFolder.isShared ? "folder.fill.badge.person.crop" : "folder.fill")
                            .foregroundStyle(currentFolder.isShared ? .orange : .blue)
                        Text(currentFolder.name)
                            .fontWeight(.medium)
                        Spacer()
                        if currentFolder.id == selectedFolder?.id && currentFolder.storageType == selectedFolder?.storageType {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFolder = currentFolder
                    }
                } header: {
                    Text("Current Folder")
                }
            }

            // サブフォルダ一覧
            Section {
                if folders.isEmpty {
                    Text("No subfolders")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(folders) { folder in
                        folderRow(folder)
                    }
                }
            } header: {
                Text(isInSharedSection || currentFolder.id == "sharedWithMe" ? "Shared Folders" : "Subfolders")
            }

            // Google Driveでルートにいる場合は「Shared with me」セクションを表示
            if selectedStorageType == .googleDrive && currentFolder.id == "root" && !sharedFolders.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.orange)
                        Text("Shared with me")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        navigateToSharedSection()
                    }
                } header: {
                    Text("Shared")
                }
            }

            // ナビゲーションオプション
            if !navigationPath.isEmpty || !isRootFolder {
                Section {
                    if !navigationPath.isEmpty {
                        Button {
                            navigateBack()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle")
                                Text("Go to parent folder")
                            }
                        }
                    } else if let parent = parentFolder {
                        Button {
                            navigateToParent(parent)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle")
                                Text("Go to parent folder")
                            }
                        }
                    }

                    if !isRootFolder {
                        Button {
                            navigateToRoot()
                        } label: {
                            HStack {
                                Image(systemName: "house")
                                Text("Go to \(rootFolderName)")
                            }
                        }
                    }
                }
            }
        }
    }

    private var isRootFolder: Bool {
        currentFolder.id == selectedStorageType.rootFolderId
    }

    private var rootFolderName: String {
        switch selectedStorageType {
        case .googleDrive:
            return "My Drive"
        case .box:
            return "All Files"
        case .dropbox:
            return "Dropbox"
        }
    }

    private func folderRow(_ folder: CloudFolder) -> some View {
        HStack {
            Image(systemName: folder.isShared ? "folder.badge.person.crop" : "folder")
                .foregroundStyle(folder.isShared ? .orange : .blue)
            Text(folder.name)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(folder)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    await loadFolders()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        parentFolder = nil

        do {
            switch selectedStorageType {
            case .googleDrive:
                await loadGoogleDriveFolders()
            case .box:
                await loadBoxFolders()
            case .dropbox:
                await loadDropboxFolders()
            }
        }

        isLoading = false
    }

    private func loadGoogleDriveFolders() async {
        do {
            if currentFolder.id == "sharedWithMe" {
                folders = try await storageManager.listSharedFolders(storageType: .googleDrive)
            } else if currentFolder.isShared || isInSharedSection {
                folders = try await storageManager.listFolders(in: currentFolder.id, storageType: .googleDrive)
                // 共有フォルダのサブフォルダとしてマーク
                folders = folders.map { folder in
                    CloudFolder(id: folder.id, name: folder.name, parentId: folder.parentId, isShared: true, storageType: .googleDrive)
                }

                // 親フォルダ情報を取得
                if navigationPath.isEmpty {
                    var parentId = currentFolder.parentId
                    if parentId == nil {
                        if let metadata = try await storageManager.getFolderMetadata(folderId: currentFolder.id, storageType: .googleDrive) {
                            parentId = metadata.parentId
                        }
                    }

                    if let parentId = parentId {
                        parentFolder = try await storageManager.getParentFolder(parentId: parentId, storageType: .googleDrive)
                        if var parent = parentFolder {
                            parentFolder = CloudFolder(id: parent.id, name: parent.name, parentId: parent.parentId, isShared: true, storageType: .googleDrive)
                        }
                    }
                }
            } else {
                folders = try await storageManager.listFolders(in: currentFolder.id, storageType: .googleDrive)

                if currentFolder.id == "root" {
                    sharedFolders = try await storageManager.listSharedFolders(storageType: .googleDrive)
                } else if navigationPath.isEmpty {
                    if let metadata = try await storageManager.getFolderMetadata(folderId: currentFolder.id, storageType: .googleDrive),
                       let parentId = metadata.parentId {
                        if parentId == "root" {
                            parentFolder = .googleDriveRoot
                        } else {
                            parentFolder = try await storageManager.getParentFolder(parentId: parentId, storageType: .googleDrive)
                        }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadBoxFolders() async {
        do {
            folders = try await storageManager.listFolders(in: currentFolder.id, storageType: .box)

            if currentFolder.id == "0" {
                sharedFolders = try await storageManager.listSharedFolders(storageType: .box)
            } else if navigationPath.isEmpty {
                if let metadata = try await storageManager.getFolderMetadata(folderId: currentFolder.id, storageType: .box),
                   let parentId = metadata.parentId {
                    if parentId == "0" {
                        parentFolder = .boxRoot
                    } else {
                        parentFolder = try await storageManager.getParentFolder(parentId: parentId, storageType: .box)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDropboxFolders() async {
        do {
            folders = try await storageManager.listFolders(in: currentFolder.id, storageType: .dropbox)

            if currentFolder.id.isEmpty {
                sharedFolders = try await storageManager.listSharedFolders(storageType: .dropbox)
            } else if navigationPath.isEmpty {
                if let metadata = try await storageManager.getFolderMetadata(folderId: currentFolder.id, storageType: .dropbox),
                   let parentId = metadata.parentId {
                    if parentId.isEmpty {
                        parentFolder = .dropboxRoot
                    } else {
                        parentFolder = try await storageManager.getParentFolder(parentId: parentId, storageType: .dropbox)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func navigateTo(_ folder: CloudFolder) {
        navigationPath.append(currentFolder)
        currentFolder = folder
        if folder.isShared {
            isInSharedSection = true
        }
        Task {
            await loadFolders()
        }
    }

    private func navigateToSharedSection() {
        navigationPath.append(currentFolder)
        currentFolder = .googleDriveSharedWithMe
        isInSharedSection = true
        Task {
            await loadFolders()
        }
    }

    private func navigateBack() {
        guard let previousFolder = navigationPath.popLast() else { return }
        currentFolder = previousFolder

        if previousFolder.id == selectedStorageType.rootFolderId {
            isInSharedSection = false
        }

        Task {
            await loadFolders()
        }
    }

    private func navigateToRoot() {
        navigationPath = []
        currentFolder = .root(for: selectedStorageType)
        isInSharedSection = false
        Task {
            await loadFolders()
        }
    }

    private func navigateToParent(_ parent: CloudFolder) {
        currentFolder = parent
        if parent.id == selectedStorageType.rootFolderId {
            isInSharedSection = false
        }
        Task {
            await loadFolders()
        }
    }
}
