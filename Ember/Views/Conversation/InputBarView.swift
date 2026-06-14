import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    var onGenerateImage: (() -> Void)? = nil
    var isImagePlaygroundLoading = false

    @FocusState private var focused: Bool

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let onGenerateImage {
                imageButton(action: onGenerateImage)
            }

            textField

            actionButton
        }
        .padding(10)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.spring(duration: 0.25), value: isStreaming)
        .animation(.spring(duration: 0.2), value: isImagePlaygroundLoading)
    }

    // MARK: - Subviews

    private var textField: some View {
        TextField("Message", text: $text, axis: .vertical)
            .focused($focused)
            .lineLimit(1...6)
            .submitLabel(.send)
            .onSubmit {
                if canSend { sendAndClear() }
            }
            .padding(.vertical, 4)
    }

    private func imageButton(action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                if isImagePlaygroundLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isStreaming || isImagePlaygroundLoading)
    }

    private var actionButton: some View {
        Group {
            if isStreaming {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    sendAndClear()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Actions

    private func sendAndClear() {
        onSend()
        focused = true
    }
}
