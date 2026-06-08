import SwiftUI

struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "iphone.gen3.slash")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Text("Ember needs an iPhone 15 Pro or newer.")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("On-device AI requires the Neural Engine and 8GB of RAM in A17 Pro and later chips. We don't support older devices because the model quality would not meet Ember's bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    UnsupportedDeviceView()
}
