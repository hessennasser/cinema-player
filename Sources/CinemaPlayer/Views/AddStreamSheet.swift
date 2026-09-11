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
    @State private var work: Task<Void, Never>?
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
                Text("Paste a video file, an HLS playlist, or a page that publicly exposes a video. Providers that need their own player, a sign-in, or DRM cannot be opened.")
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
        .onDisappear { work?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "link")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CinemaTheme.electricBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open a video link")
                    .font(.headline)
                Text("Direct video links, and pages that expose one.")
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
            Button(isResolving ? "Stop" : "Cancel", role: .cancel) {
                if isResolving {
                    work?.cancel()
                    isResolving = false
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
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
        // Replaces any check still running, so a corrected address does not
        // race the one it replaced.
        work?.cancel()
        work = Task {
            do {
                try await add(address)
                guard !Task.isCancelled else { return }
                dismiss()
            } catch is CancellationError {
                // The sheet closed or another check took over.
            } catch {
                guard !Task.isCancelled else { return }
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
