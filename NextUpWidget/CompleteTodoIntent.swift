import AppIntents
import Foundation
import NextUpShared

struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var openAppWhenRun = false

    @Parameter(title: "Task")
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
            let repository = try TodoRepository.inAppGroup()
            _ = try repository.setStatus(id: id, status: .done, now: Date())
        } catch {
            // 任务已被删除或暂时读不到：不打开应用，也不报错，下一次刷新会显示最新状态。
            return .result()
        }
        AppIdentity.reloadWidgets()
        return .result()
    }
}
