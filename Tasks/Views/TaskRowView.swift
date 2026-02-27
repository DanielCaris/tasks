import SwiftUI
import SwiftData

struct TaskRowView: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.externalId)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    if task.priorityScore > 0 {
                        Text(String(format: "%.1f", task.priorityScore))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                Text(task.title)
                    .lineLimit(2)
                    .font(.body)
            }

            Spacer()

            if task.urgency != nil || task.impact != nil || task.effort != nil {
                HStack(spacing: 4) {
                    if let u = task.urgency {
                        Label("\(u)", systemImage: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if let i = task.impact {
                        Label("\(i)", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if let e = task.effort {
                        Label("\(e)", systemImage: "clock.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
