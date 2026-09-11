import AppKit
import SwiftUI

/// Accepts a video link so the library is not limited to what is on this Mac.
struct AddStreamSheet: View {
    let add: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var isAddressFocused: Bool

    private var isValid: Bool {
        StreamSupport.streamURL(from: address) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "link")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CinemaTheme.electricBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open a video link")
                        .font(.headline)
                    Text("Paste a direct video address or an HLS playlist.")
                        .font(.caption)
                        .foregroundStyle(CinemaTheme.quietText)
                }
            }

            HStack(spacing: 8) {
                TextField("https://example.com/movie.mp4", text: $address)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .focused($isAddressFocused)
                    .onSubmit(submit)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }

                Button("Paste", action: pasteFromClipboard)
                    .buttonStyle(.bordered)
                    .help("Paste the link on the clipboard")
            }

            Text("Cinema Player plays whatever macOS can decode — MP4, MOV, and HLS streams work best. Links to a web page rather than a video file will not play.")
                .font(.caption)
                .foregroundStyle(CinemaTheme.quietText)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Link", action: submit)
                    .buttonStyle(.borderedProminent)
                    .tint(CinemaTheme.electricBlue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(22)
        .frame(width: 470)
        .background(CinemaTheme.night)
        .foregroundStyle(.white)
        .onAppear { isAddressFocused = true }
    }

    private func submit() {
        guard isValid else { return }
        add(address)
        dismiss()
    }

    private func pasteFromClipboard() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        address = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
