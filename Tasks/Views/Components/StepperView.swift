import SwiftUI

/// Stepper nativo para U/I/E: icono + control nativo de macOS
struct StepperView: View {
    let label: String
    let icon: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...5

    var body: some View {
        HStack(spacing: 6) {
            Label(label, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 14, alignment: .center)

            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        StepperView(label: "Urgencia", icon: "clock.fill", value: .constant(5))
        StepperView(label: "Impacto", icon: "bolt.fill", value: .constant(4))
        StepperView(label: "Esfuerzo", icon: "hammer.fill", value: .constant(2))
    }
    .padding()
}
