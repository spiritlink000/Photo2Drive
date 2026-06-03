//
//  StorageAccountsView.swift
//  Photo2drive
//

import SwiftUI

/// View for managing cloud storage account connections.
struct StorageAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    let storageManager: CloudStorageManager

    @State private var isSigningIn: StorageType?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(StorageType.allCases) { storageType in
                    storageRow(for: storageType)
                }
            }
            .navigationTitle("Storage Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func storageRow(for storageType: StorageType) -> some View {
        HStack {
            Image(systemName: storageType.iconName)
                .font(.title2)
                .foregroundStyle(iconColor(for: storageType))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(storageType.displayName)
                    .font(.headline)

                if storageManager.isAuthenticated(for: storageType),
                   let userName = storageManager.userName(for: storageType) {
                    Text(userName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSigningIn == storageType {
                ProgressView()
            } else if storageManager.isAuthenticated(for: storageType) {
                Button("Sign Out") {
                    storageManager.signOut(from: storageType)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("Sign In") {
                    signIn(to: storageType)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
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

    private func signIn(to storageType: StorageType) {
        isSigningIn = storageType

        Task {
            do {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let viewController = windowScene.windows.first?.rootViewController else {
                    throw CloudStorageError.authenticationFailed("No view controller available")
                }

                try await storageManager.signIn(to: storageType, from: viewController)
            } catch {
                errorMessage = error.localizedDescription
            }

            isSigningIn = nil
        }
    }
}
