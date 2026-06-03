//
//  CloudStorageError.swift
//  Photo2drive
//

import Foundation

/// Common error types for cloud storage operations.
enum CloudStorageError: LocalizedError {
    case notAuthenticated
    case authenticationFailed(String)
    case invalidResponse
    case uploadFailed(String)
    case listFailed(String)
    case networkError(String)
    case tokenRefreshFailed
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .listFailed(let message):
            return "Failed to list folders: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .unsupportedOperation:
            return "This operation is not supported"
        }
    }
}
