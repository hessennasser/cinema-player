import AppKit
import SwiftUI

/// Accepts a video link so the library is not limited to what is on this Mac.
/// Resolving a link touches the network, so the sheet stays open and reports
/// what happened rather than dismissing into an alert.
struct AddStreamSheet: View {
    let add: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var isResolving = false
    @State private var failure: String?
    @FocusState private var isAddressFocused: Bool

    private var isValid: Bool {
        StreamSupport.streamURL(from: address) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            addressField

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(CinemaTheme.signalRed)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Paste a video file, an HLS playlist, or the address of a page that hosts a video — Cinema Player will look for the video on it.")
                    .font(.caption)
                    .foregroundStyle(CinemaTheme.quietText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(22)
        .frame(width: 470)
        .background(CinemaTheme.night)
        .foregroundStyle(.white)
        .onAppear { isAddressFocused = true }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "link")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CinemaTheme.electricBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open a video link")
                    .font(.headline)
                Text("Play a video from anywhere on the web.")
                    .font(.caption)
                    .foregroundStyle(CinemaTheme.quietText)
            }
        }
    }

    private var addressField: some View {
        HStack(spacing: 8) {
            TextField("https://example.com/movie.mp4", text: $address)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .focused($isAddressFocused)
                .onSubmit(submit)
                .onChange(of: address) { _, _ in failure = nil }
                .disabled(isResolving)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(failure == nil ? .white.opacity(0.1) : CinemaTheme.signalRed.opacity(0.6), lineWidth: 1)
                }

            Button("Paste", action: pasteFromClipboard)
                .buttonStyle(.bordered)
                .disabled(isResolving)
                .help("Paste the link on the clipboard")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isResolving {
                ProgressView()
                    .controlSize(.small)
                Text("Checking the link…")
                    .font(.caption)
                    .foregroundStyle(CinemaTheme.quietText)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isResolving)
            Button("Add Link", action: submit)
                .buttonStyle(.borderedProminent)
                .tint(CinemaTheme.electricBlue)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isResolving)
        }
    }

    private func submit() {
        guard isValid, !isResolving else { return }

        isResolving = true
        failure = nil
        Task {
            do {
                try await add(address)
                dismiss()
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isResolving = false
        }
    }

    private func pasteFromClipboard() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        address = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        failure = nil
    }
}
