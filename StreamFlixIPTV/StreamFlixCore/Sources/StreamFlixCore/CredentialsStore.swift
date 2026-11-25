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
        var needsMigration = false
        let hydrated: [XtreamCredentials] = decoded.map { cred in
            let accountKey = keychainAccount(for: cred)
            if let keychainPass = KeychainHelper.load(account: accountKey), !keychainPass.isEmpty {
                return XtreamCredentials(
                    host: cred.host,
                    username: cred.username,
                    password: keychainPass,
                    profileName: cred.profileName
                )
            } else if !cred.password.isEmpty {
                KeychainHelper.save(cred.password, account: accountKey)
                needsMigration = true
            }
            return cred
        }
        savedProfiles = hydrated
        if needsMigration {
            persist()
        }
        let wasSignedOut = UserDefaults.standard.bool(forKey: signedOutKey)
        activeProfile = wasSignedOut ? nil : hydrated.first
    }

    private func persist() {
        // Save passwords in encrypted Keychain and scrub them from UserDefaults
        let sanitized = savedProfiles.map { cred -> XtreamCredentials in
            let accountKey = keychainAccount(for: cred)
            if !cred.password.isEmpty {
                KeychainHelper.save(cred.password, account: accountKey)
            }
            return XtreamCredentials(
                host: cred.host,
                username: cred.username,
                password: "",
                profileName: cred.profileName
            )
        }
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func keychainAccount(for cred: XtreamCredentials) -> String {
        "xtream:\(cred.host)|\(cred.username)"
    }
}
