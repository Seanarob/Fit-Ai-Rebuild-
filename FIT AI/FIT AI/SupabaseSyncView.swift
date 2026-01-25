import SwiftUI

struct SupabaseSyncView: View {
    @StateObject private var viewModel = SupabaseViewModel()
    @State private var email: String = ""
    @State private var password: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                loginSection
                profileSection
                statusSection
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("FIT AI + Supabase")
        .task {
            await viewModel.refreshProfiles()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync with Supabase")
                .font(FitFont.heading(size: 22))
                .fontWeight(.bold)
            Text("Install the Supabase Swift client via Swift Package Manager, then update Supabase.plist with your project URL and anon key.")
                .font(FitFont.body(size: 15))
                .foregroundColor(.secondary)
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authenticate")
                .font(FitFont.body(size: 17, weight: .semibold))
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(10)

            Button("Sign in with Supabase") {
                Task {
                    await viewModel.signIn(email: email.trimmingCharacters(in: .whitespaces),
                                           password: password)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isLoading)
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(14)
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent profiles")
                    .font(FitFont.body(size: 17, weight: .semibold))
                Spacer()
                Button("Refresh") {
                    Task {
                        await viewModel.refreshProfiles()
                    }
                }
                .disabled(viewModel.isLoading)
            }

            if viewModel.isLoading && viewModel.profiles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.profiles.isEmpty {
                Text("No profiles yet. Push to Supabase and try again.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.profiles) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.fullName ?? profile.username ?? profile.id)
                                .fontWeight(.semibold)
                            Text(profile.email ?? "No email")
                                .font(FitFont.body(size: 12))
                                .foregroundColor(.secondary)
                            if let role = profile.role {
                                Text(role)
                                    .font(FitFont.body(size: 11))
                                    .italic()
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(14)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(FitFont.body(size: 13))
                    .foregroundColor(.secondary)
            }
            if viewModel.isLoading {
                ProgressView("Syncing...")
                    .progressViewStyle(.linear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SupabaseSyncView()
}
