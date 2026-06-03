//
//  FolderPickerView.swift
//  Photo2drive
//

import SwiftUI

/// View for selecting a Google Drive folder.
struct FolderPickerView: View {
    @Binding var selectedFolder: DriveFolder
    let authService: GoogleAuthService
    let onDismiss: () -> Void

    @State private var folders: [DriveFolder] = []
    @State private var sharedFolders: [DriveFolder] = []
    @State private var currentFolder: DriveFolder
    @State private var navigationPath: [DriveFolder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isInSharedSection: Bool
    @State private var parentFolder: DriveFolder?

    private let driveService = GoogleDriveService()

    init(selectedFolder: Binding<DriveFolder>, authService: GoogleAuthService, onDismiss: @escaping () -> Void) {
        self._selectedFolder = selectedFolder
        self.authService = authService
        self.onDismiss = onDismiss

        // 選択済みフォルダがある場合はそのフォルダから開始
        let folder = selectedFolder.wrappedValue
        if folder.id != "root" {
            self._currentFolder = State(initialValue: folder)
            self._isInSharedSection = State(initialValue: folder.isShared)
        } else {
            self._currentFolder = State(initialValue: .root)
            self._isInSharedSection = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading folders...")
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
                    // sharedWithMeセクション自体は選択不可
                    .disabled(currentFolder.id == "sharedWithMe")
                }
            }
        }
        .task {
            await loadFolders()
        }
    }

    private var folderListView: some View {
        List {
            // 現在のフォルダを選択するオプション（sharedWithMeセクション以外）
            if currentFolder.id != "sharedWithMe" {
                Section {
                    HStack {
                        Image(systemName: currentFolder.isShared ? "folder.fill.badge.person.crop" : "folder.fill")
                            .foregroundStyle(currentFolder.isShared ? .orange : .blue)
                        Text(currentFolder.name)
                            .fontWeight(.medium)
                        Spacer()
                        if currentFolder.id == selectedFolder.id {
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
                Text(currentFolder.id == "sharedWithMe" ? "Shared Folders" : "Subfolders")
            }

            // ルートにいる場合は「共有アイテム」セクションを表示
            if currentFolder.id == "root" && !sharedFolders.isEmpty {
                Section {
                    // 共有アイテムセクションへ移動
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
            if !navigationPath.isEmpty || currentFolder.id != "root" {
                Section {
                    // ナビゲーションパスがある場合は通常の戻る
                    if !navigationPath.isEmpty {
                        Button {
                            navigateBack()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle")
                                Text("Go to parent folder")
                            }
                        }
                    }
                    // ナビゲーションパスがないが親フォルダがある場合（アプリ起動時）
                    else if let parent = parentFolder {
                        Button {
                            navigateToParent(parent)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle")
                                Text("Go to parent folder")
                            }
                        }
                    }

                    // ルート以外にいる場合はMy Driveに戻るオプションを表示
                    if currentFolder.id != "root" {
                        Button {
                            navigateToRoot()
                        } label: {
                            HStack {
                                Image(systemName: "house")
                                Text("Go to My Drive")
                            }
                        }
                    }
                }
            }
        }
    }

    private func folderRow(_ folder: DriveFolder) -> some View {
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
    }

    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        parentFolder = nil

        do {
            let accessToken = try await authService.getAccessToken()

            if currentFolder.id == "sharedWithMe" {
                // 共有フォルダ一覧を表示
                folders = try await driveService.listSharedFolders(accessToken: accessToken)
            } else if currentFolder.isShared || isInSharedSection {
                // 共有フォルダのサブフォルダを取得
                folders = try await driveService.listSharedSubfolders(in: currentFolder.id, accessToken: accessToken)

                // 親フォルダ情報を取得（ナビゲーションパスがない場合）
                if navigationPath.isEmpty {
                    // currentFolder.parentIdがnilの場合（設定から読み込んだ場合）、APIから取得
                    var parentId = currentFolder.parentId
                    if parentId == nil {
                        if let metadata = try await driveService.getFolderMetadata(folderId: currentFolder.id, accessToken: accessToken) {
                            parentId = metadata.parentId
                        }
                    }

                    if let parentId = parentId {
                        parentFolder = try await driveService.getParentFolder(parentId: parentId, accessToken: accessToken)
                        parentFolder = parentFolder.map { DriveFolder(id: $0.id, name: $0.name, parentId: $0.parentId, isShared: true) }
                    }
                }
            } else {
                // 通常のフォルダ一覧を取得
                folders = try await driveService.listFolders(in: currentFolder.id, accessToken: accessToken)

                // ルートの場合は共有フォルダも取得
                if currentFolder.id == "root" {
                    sharedFolders = try await driveService.listSharedFolders(accessToken: accessToken)
                } else if navigationPath.isEmpty {
                    // ナビゲーションパスがない場合は親フォルダ情報を取得
                    if let metadata = try await driveService.getFolderMetadata(folderId: currentFolder.id, accessToken: accessToken),
                       let parentId = metadata.parentId {
                        if parentId == "root" {
                            parentFolder = .root
                        } else {
                            parentFolder = try await driveService.getParentFolder(parentId: parentId, accessToken: accessToken)
                        }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func navigateTo(_ folder: DriveFolder) {
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
        currentFolder = .sharedWithMe
        isInSharedSection = true
        Task {
            await loadFolders()
        }
    }

    private func navigateBack() {
        guard let previousFolder = navigationPath.popLast() else { return }
        currentFolder = previousFolder

        // ルートに戻ったら共有セクションフラグをリセット
        if previousFolder.id == "root" {
            isInSharedSection = false
        }

        Task {
            await loadFolders()
        }
    }

    private func navigateToRoot() {
        navigationPath = []
        currentFolder = .root
        isInSharedSection = false
        Task {
            await loadFolders()
        }
    }

    private func navigateToParent(_ parent: DriveFolder) {
        // 現在のフォルダをナビゲーションパスに追加せず、親に移動
        currentFolder = parent
        if parent.id == "root" {
            isInSharedSection = false
        }
        Task {
            await loadFolders()
        }
    }
}
