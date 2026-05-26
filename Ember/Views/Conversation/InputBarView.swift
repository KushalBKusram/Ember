import SwiftUI
import Speech

struct InputBarView: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @StateObject private var speech = SpeechService.shared
    @FocusState private var focused: Bool
    @State private var isRecording = false

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            voiceButton

            textField

            actionButton
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .onChange(of: speech.transcribedText) { _, new in
            if !new.isEmpty { text = new }
        }
        .animation(.spring(duration: 0.25), value: isStreaming)
        .animation(.spring(duration: 0.25), value: speech.isRecording)
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

    private var voiceButton: some View {
        Button {
            toggleRecording()
        } label: {
            Image(systemName: speech.isRecording ? "waveform" : "mic")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(speech.isRecording ? .orange : .secondary)
                .frame(width: 32, height: 32)
                .symbolEffect(.variableColor.cumulative, isActive: speech.isRecording)
        }
        .buttonStyle(.plain)
    }

    private var actionButton: some View {
        Group {
            if isStreaming {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    sendAndClear()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Actions

    private func sendAndClear() {
        speech.stopRecording()
        speech.transcribedText = ""
        onSend()
        focused = true
    }

    private func toggleRecording() {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            Task {
                if speech.authorizationStatus != .authorized {
                    await speech.requestAuthorization()
                }
                guard speech.authorizationStatus == .authorized else { return }
                text = ""
                speech.transcribedText = ""
                try? speech.startRecording()
            }
        }
    }
}
