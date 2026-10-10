import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Spacer()
            HStack(spacing: Space.s) {
                BrandMark()
                    .frame(width: 32, height: 32)
                Text("KilnWatch")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text("Satellite evidence for kiln inspections in NCR: which kilns to visit, why, and in what order.")
                .font(.body)
                .foregroundStyle(.inkSecondary)
            Spacer()
            Spacer()
            Button("Sign in with department account") {
                withAnimation(.easeInOut(duration: 0.3)) { model.signedIn = true }
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.canvas)
    }
}

/// The mark: a rotated rounded rectangle outline, echoing the oriented box the detector draws.
struct BrandMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            RoundedRectangle(cornerRadius: side * 0.1, style: .continuous)
                .stroke(.clay, lineWidth: max(2, side * 0.08))
                .frame(width: side * 0.6, height: side * 0.3)
                .rotationEffect(.degrees(-28))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SignInView().environment(AppModel())
}
