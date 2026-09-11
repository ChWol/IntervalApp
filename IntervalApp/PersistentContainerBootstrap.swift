import SwiftData
import SwiftUI

struct ContainerBootstrapResult {
    let container: ModelContainer
    let startupError: String?
}

enum PersistentContainerBootstrap {
    static func load(schema: Schema) -> ContainerBootstrapResult {
        choose(
            primary: {
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                return try ModelContainer(for: schema, configurations: [configuration])
            },
            fallback: {
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [configuration])
            }
        )
    }

    static func choose(
        primary: () throws -> ModelContainer,
        fallback: () throws -> ModelContainer
    ) -> ContainerBootstrapResult {
        do {
            return ContainerBootstrapResult(container: try primary(), startupError: nil)
        } catch {
            let primaryError = error.localizedDescription
            do {
                return ContainerBootstrapResult(
                    container: try fallback(),
                    startupError: "Interval could not safely open its local data. The original store has been left untouched. Close and reopen the app; if this continues, keep the app installed and contact support. \(primaryError)"
                )
            } catch {
                fatalError("Could not create either persistent or recovery ModelContainer: \(error)")
            }
        }
    }
}

struct DataStoreUnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("Your data could not be opened")
                .font(.system(size: 17, weight: .medium))
            Text(message)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(32)
    }
}
