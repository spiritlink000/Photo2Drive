//
//  CloudStorageAuthService.swift
//  Photo2drive
//

import UIKit

/// Protocol for cloud storage authentication services.
@MainActor
protocol CloudStorageAuthService: AnyObject {
    /// The type of storage this service handles.
    var storageType: StorageType { get }

    /// Whether the user is currently authenticated.
    var isAuthenticated: Bool { get }

    /// The display name of the authenticated user, if available.
    var userDisplayName: String? { get }

    /// Signs in the user.
    /// - Parameter viewController: The view controller to present the sign-in UI from.
    func signIn(from viewController: UIViewController) async throws

    /// Signs out the current user.
    func signOut()

    /// Gets a valid access token, refreshing if necessary.
    /// - Returns: A valid access token.
    func getAccessToken() async throws -> String

    /// Handles the OAuth callback URL.
    /// - Parameter url: The callback URL.
    /// - Returns: True if the URL was handled.
    func handleURL(_ url: URL) -> Bool
}
