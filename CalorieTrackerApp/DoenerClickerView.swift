import SwiftUI

struct DoenerClickerView: View {
    @EnvironmentObject private var language: LanguageStore
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    @State private var clicks = 0
    @State private var scale: CGFloat = 1.0
    @State private var floatingTexts: [(id: UUID, text: String, x: CGFloat, y: CGFloat)] = []

    var body: some View {
        VStack(spacing: 20) {
            Text("ui.kebab_clicker")
                .font(.largeTitle)
                .bold()

            Text(t("doener_clicker.kebabs_clicked_1", String(describing: clicks)))
                .font(.title2)
                .foregroundColor(.secondary)

            ZStack {
                // 1. Der Klick-Döner (Hintergrund)
                Button {
                    clickDoener()
                } label: {
                    Text("🌯")
                        .font(.system(size: 130))
                        .scaleEffect(scale)
                }
                .buttonStyle(.plain)

                // 2. Fliegende Zahlen-Effekte (Vordergrund - liegt über dem Döner)
                ForEach(floatingTexts, id: \.id) { item in
                    Text(item.text)
                        .font(.title)
                        .bold()
                        .foregroundColor(HyseColor.accent)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
                        .offset(x: item.x, y: item.y)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
            .frame(height: 250)

            Text("ui.every_kebab_burns_0_0001_calories_through")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 30)
    }

    private func clickDoener() {
        clicks += 1

        withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
            scale = 1.3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation { scale = 1.0 }
        }

        let id = UUID()
        let randomX = CGFloat.random(in: -70...70)
        let randomY = CGFloat.random(in: -90 ... -40)
        let newText: (id: UUID, text: String, x: CGFloat, y: CGFloat) = (id: id, text: "+1 🌯", x: randomX, y: randomY)

        withAnimation(.easeOut(duration: 0.3)) {
            floatingTexts.append(newText)
        }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation {
                floatingTexts.removeAll { $0.id == id }
            }
        }
    }
}
