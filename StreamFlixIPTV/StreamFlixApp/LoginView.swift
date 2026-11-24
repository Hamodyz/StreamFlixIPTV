import SwiftUI
import StreamFlixCore

struct LoginView: View {
    @ObservedObject var credentialsStore: CredentialsStore

    @State private var profileName = "My IPTV"
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [Color(red: 0.55, green: 0.0, blue: 0.05).opacity(0.45), .black],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("STREAMFLIX")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.898, green: 0.035, blue: 0.078))
                            .tracking(3)
                        Text("Sign in with your Xtream Codes IPTV account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    if !credentialsStore.savedProfiles.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Who's Watching?")
                                .font(.headline)
                                .foregroundStyle(.white)

                            ForEach(credentialsStore.savedProfiles, id: \.username) { profile in
                                Button {
                                    credentialsStore.selectProfile(profile)
                                } label: {
                                    HStack(spacing: 14) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(red: 0.898, green: 0.035, blue: 0.078))
                                            .frame(width: 44, height: 44)
                                            .overlay {
                                                Image(systemName: "person.fill")
                                                    .foregroundStyle(.white)
                                            }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profile.profileName)
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                            Text("\(profile.username) • \(profile.host)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .frame(maxWidth: 460)
                    }

                    VStack(spacing: 14) {
                        TextField("Profile Name (e.g. Home TV)", text: $profileName)
                            .textFieldStyle(NetflixFieldStyle())
                        TextField("Host URL (e.g. http://server.com:8080)", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textFieldStyle(NetflixFieldStyle())
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(NetflixFieldStyle())
                        SecureField("Password", text: $password)
                            .textFieldStyle(NetflixFieldStyle())

                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await connect() }
                        } label: {
                            HStack {
                                if isTesting { ProgressView().tint(.white) }
                                Text(isTesting ? "Connecting..." : "Sign In")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 0.898, green: 0.035, blue: 0.078))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(isTesting || host.isEmpty || username.isEmpty || password.isEmpty)
                    }
                    .frame(maxWidth: 460)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func connect() async {
        isTesting = true
        errorText = nil
        let creds = XtreamCredentials(
            host: host,
            username: username,
            password: password,
            profileName: profileName.isEmpty ? "My IPTV" : profileName
        )
        let client = XtreamAPIClient(credentials: creds)
        do {
            _ = try await client.authenticate()
            credentialsStore.saveAndActivate(creds)
        } catch {
            errorText = error.localizedDescription
        }
        isTesting = false
    }
}

struct NetflixFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(Color.white.opacity(0.12))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
