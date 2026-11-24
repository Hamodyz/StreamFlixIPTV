import Foundation
import Combine

@MainActor
public final class CredentialsStore: ObservableObject {
    @Published public private(set) var savedProfiles: [XtreamCredentials] = []
    @Published public var activeProfile: XtreamCredentials?

    private let storageKey = "StreamFlixIPTV.SavedProfiles.v1"
    private let signedOutKey = "StreamFlixIPTV.ExplicitlySignedOut.v1"

    public init() {
        load()
    }

    public func saveAndActivate(_ credentials: XtreamCredentials) {
        if let idx = savedProfiles.firstIndex(where: {
            $0.host == credentials.host && $0.username == credentials.username
        }) {
            savedProfiles[idx] = credentials
        } else {
            savedProfiles.insert(credentials, at: 0)
        }
        activeProfile = credentials
        UserDefaults.standard.set(false, forKey: signedOutKey)
        persist()
    }

    public func selectProfile(_ credentials: XtreamCredentials) {
        activeProfile = credentials
        UserDefaults.standard.set(false, forKey: signedOutKey)
    }

    public func signOut() {
        activeProfile = nil
        UserDefaults.standard.set(true, forKey: signedOutKey)
    }

    public func deleteProfile(_ credentials: XtreamCredentials) {
        savedProfiles.removeAll { $0 == credentials }
        if activeProfile == credentials {
            activeProfile = nil
        }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([XtreamCredentials].self, from: data) else {
            return
        }
        savedProfiles = decoded
        let wasSignedOut = UserDefaults.standard.bool(forKey: signedOutKey)
        activeProfile = wasSignedOut ? nil : decoded.first
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedProfiles) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
