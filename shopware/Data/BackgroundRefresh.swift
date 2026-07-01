import Foundation
#if os(iOS)
import BackgroundTasks
import UIKit
#endif

/// Schedules and handles periodic background snapshot refresh on iOS via `BGAppRefreshTask`.
/// On macOS this is a no-op (the app stays resident; refresh happens on foreground/manual).
enum BackgroundRefresh {
    static let taskIdentifier = "de.shyim.shopware.refresh"

    /// Registers the launch handler. Call once at app launch, before the app finishes launching.
    @MainActor
    static func register(model: AppViewModel) {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(refreshTask, model: model)
        }
        #endif
    }

    /// Schedules the next refresh (~15 min out), mirroring the Android SyncWorker interval.
    static func schedule() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    static func cancel() {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        #endif
    }

    #if os(iOS)
    @MainActor
    private static func handle(_ task: BGAppRefreshTask, model: AppViewModel) {
        schedule() // chain the next one
        let work = Task {
            let didRefresh = await SyncService(repo: model.repo).runOnce()
            task.setTaskCompleted(success: didRefresh)
        }
        task.expirationHandler = { work.cancel() }
    }
    #endif
}
