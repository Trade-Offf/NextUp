import AppIntents
import Foundation
import NextUpShared
import WidgetKit

struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "完成任务"
    static var openAppWhenRun = false

    @Parameter(title: "任务")
    var itemID: String

    init() {
        self.itemID = ""
    }

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        do {
            // let repository = try TodoRepository.inAppGroup()
            let repository = try TodoRepository.localStore()
            _ = try repository.setStatus(id: id, status: .done, now: Date())
        } catch StoreError.notFound {
            return .result()
        } catch {
            return .result()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: AppIdentity.widgetKind())
        return .result()
    }
}
