//
//  UploadView.swift
//  Photo2drive
//

import SwiftUI

/// View displaying upload progress and status.
struct UploadView: View {
    @Bindable var viewModel: UploadViewModel
    let authService: GoogleAuthService
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 全体進捗
                overallProgressSection

                // 個別アイテムの進捗
                uploadItemsList

                Spacer()

                // アクションボタン
                actionButtons
            }
            .padding()
            .navigationTitle("Upload")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.startUpload(authService: authService)
        }
    }

    private var overallProgressSection: some View {
        VStack(spacing: 12) {
            if viewModel.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("Upload Complete!")
                    .font(.title2)
                    .fontWeight(.semibold)
            } else if viewModel.isUploading {
                ProgressView(value: viewModel.overallProgress) {
                    Text("Uploading...")
                        .font(.headline)
                } currentValueLabel: {
                    Text("\(viewModel.completedCount) / \(viewModel.uploadItems.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
            }

            if viewModel.failedCount > 0 {
                Text("\(viewModel.failedCount) failed")
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var uploadItemsList: some View {
        List {
            ForEach(viewModel.uploadItems) { item in
                uploadItemRow(item)
            }
        }
        .listStyle(.inset)
    }

    private func uploadItemRow(_ item: UploadItem) -> some View {
        HStack {
            // サムネイル
            if let thumbnail = item.photoItem.thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.photoItem.fileName)
                    .font(.subheadline)
                    .lineLimit(1)

                statusView(for: item.status)
            }

            Spacer()

            statusIcon(for: item.status)
        }
    }

    @ViewBuilder
    private func statusView(for status: UploadStatus) -> some View {
        switch status {
        case .pending:
            Text("Waiting...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .uploading(let progress):
            ProgressView(value: progress)
                .frame(width: 100)
        case .completed:
            Text("Uploaded")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let error):
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: UploadStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .uploading:
            ProgressView()
                .scaleEffect(0.8)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if viewModel.isCompleted {
                Button {
                    onComplete()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if viewModel.failedCount > 0 && !viewModel.isUploading {
                Button {
                    Task {
                        await viewModel.retryFailed(authService: authService)
                    }
                } label: {
                    Text("Retry Failed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
