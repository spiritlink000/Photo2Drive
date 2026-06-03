//
//  UploadQuality.swift
//  Photo2drive
//

import Foundation

/// Represents the quality setting for photo uploads.
enum UploadQuality: String, CaseIterable, Identifiable, Sendable {
    case original
    case compressed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original:
            return "Original"
        case .compressed:
            return "Compressed"
        }
    }

    var description: String {
        switch self {
        case .original:
            return "Upload at full resolution"
        case .compressed:
            return "Reduce file size for faster uploads"
        }
    }

    /// JPEG compression quality (0.0 to 1.0).
    var compressionQuality: CGFloat {
        switch self {
        case .original:
            return 1.0
        case .compressed:
            return 0.7
        }
    }

    /// Maximum dimension for compressed images.
    var maxDimension: CGFloat? {
        switch self {
        case .original:
            return nil
        case .compressed:
            return 2048
        }
    }
}
