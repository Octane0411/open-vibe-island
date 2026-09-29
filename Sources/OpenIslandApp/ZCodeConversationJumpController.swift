import AppKit
import ApplicationServices
import Foundation
import SQLite3

struct ZCodeConversationRecord: Equatable, Sendable {
    let id: String
    let title: String
    let workspacePath: String
}

/// Read-only access to ZCode's task index. ZCode writes the same stable
/// `sess_*` identifier into hook payloads and the `tasks.task_id` column, so
/// this is the missing bridge between an Open Island session and the title
/// rendered in ZCode's conversation sidebar.
struct ZCodeTaskIndex: Sendable {
    let databasePath: String

    init(databasePath: String = ZCodeTaskIndex.defaultDatabasePath()) {
        self.databasePath = databasePath
    }

    static func defaultDatabasePath() -> String {
        NSHomeDirectory() + "/.zcode/v2/tasks-index.sqlite"
    }

    func conversation(id: String) -> ZCodeConversationRecord? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return nil }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &database, flags, nil) == SQLITE_OK,
              let database else {
            if database != nil {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)

        let sql = """
        SELECT title, workspace_path
        FROM tasks
        WHERE task_id = ? AND deleted = 0
        ORDER BY updated_at DESC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let heldID = normalizedID.withCString { strdup($0) }
        defer { free(heldID) }
        sqlite3_bind_text(statement, 1, heldID, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let titleValue = sqlite3_column_text(statement, 0),
              let workspaceValue = sqlite3_column_text(statement, 1) else {
            return nil
        }

        let title = String(cString: titleValue).trimmingCharacters(in: .whitespacesAndNewlines)
        let workspacePath = String(cString: workspaceValue)
        guard !title.isEmpty else { return nil }

        return ZCodeConversationRecord(
            id: normalizedID,
            title: title,
            workspacePath: workspacePath
        )
    }
}

enum ZCodeConversationFocusResult: Equatable, Sendable {
    case focused
    case unavailable(String)
}

/// Focuses a ZCode conversation without reopening its workspace. ZCode 3.14
/// does not route conversation IDs through its URL scheme, but its task index
/// and Chromium accessibility tree expose enough stable information to press
/// the exact existing sidebar entry and verify the resulting page heading.
struct ZCodeConversationJumpController: Sendable {
    typealias Sleeper = @Sendable (TimeInterval) -> Void
    typealias MonotonicClock = @Sendable () -> TimeInterval

    private let taskIndex: ZCodeTaskIndex
    private let sleeper: Sleeper
    private let clock: MonotonicClock
    private let focusTimeout: TimeInterval

    init(
        taskIndex: ZCodeTaskIndex = ZCodeTaskIndex(),
        sleeper: @escaping Sleeper = { Thread.sleep(forTimeInterval: $0) },
        clock: @escaping MonotonicClock = { ProcessInfo.processInfo.systemUptime },
        focusTimeout: TimeInterval = 3
    ) {
        self.taskIndex = taskIndex
        self.sleeper = sleeper
        self.clock = clock
        self.focusTimeout = max(0, focusTimeout)
    }

    func focus(conversationID: String) -> ZCodeConversationFocusResult {
        let deadline = clock() + focusTimeout
        guard let conversation = taskIndex.conversation(id: conversationID) else {
            return .unavailable("task-index-miss")
        }
        guard hasTimeRemaining(before: deadline) else {
            return .unavailable("focus-timeout")
        }
        guard AXIsProcessTrusted() else {
            return .unavailable("accessibility-unavailable")
        }
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: "dev.zcode.app")
            .first(where: { $0.processIdentifier > 0 }) else {
            return .unavailable("app-not-running")
        }
        guard hasTimeRemaining(before: deadline) else {
            return .unavailable("focus-timeout")
        }

        // Electron may report an empty AXWindows array while ZCode is in the
        // background. Activation must happen before window lookup; waiting on
        // the hidden app alone never makes the accessibility window appear.
        application.unhide()
        guard hasTimeRemaining(before: deadline) else {
            return .unavailable("focus-timeout")
        }
        application.activate(options: [.activateAllWindows])
        guard let window = waitForWindow(of: application, before: deadline) else {
            if !hasTimeRemaining(before: deadline) {
                return .unavailable("focus-timeout")
            }
            return .unavailable("ax-window-missing")
        }

        guard raise(window: window, before: deadline) else {
            return .unavailable("focus-timeout")
        }

        let workspaceName = URL(fileURLWithPath: conversation.workspacePath).lastPathComponent
        ensureProjectsView(in: window, before: deadline)
        guard let projectsWindow = waitForWindow(of: application, before: deadline) else {
            if !hasTimeRemaining(before: deadline) {
                return .unavailable("focus-timeout")
            }
            return .unavailable("ax-window-missing-after-projects")
        }
        expandProjectIfNeeded(named: workspaceName, in: projectsWindow, before: deadline)

        if let expandedWindow = waitForWindow(of: application, before: deadline),
           pressConversation(
               title: conversation.title,
               workspaceName: workspaceName,
               in: expandedWindow,
               before: deadline
           ),
           waitUntilConversationIsActive(
               title: conversation.title,
               workspaceName: workspaceName,
               application: application,
               before: deadline
           ) {
            return .focused
        }

        // ZCode initially renders only a bounded number of conversations for
        // larger projects. Reveal additional pages and retry after each DOM
        // update. Re-resolve every AX element because Chromium node handles
        // become stale when the sidebar rerenders.
        for _ in 0..<20 where hasTimeRemaining(before: deadline) {
            guard let currentWindow = waitForWindow(of: application, before: deadline),
                  pressShowMore(
                    forProjectNamed: workspaceName,
                    in: currentWindow,
                    before: deadline
                  ) else {
                break
            }
            sleep(0.08, before: deadline)
            if let revealedWindow = waitForWindow(of: application, before: deadline),
               pressConversation(
                   title: conversation.title,
                   workspaceName: workspaceName,
                   in: revealedWindow,
                   before: deadline
               ),
               waitUntilConversationIsActive(
                   title: conversation.title,
                   workspaceName: workspaceName,
                   application: application,
                   before: deadline
               ) {
                return .focused
            }
        }

        if !hasTimeRemaining(before: deadline) {
            return .unavailable("focus-timeout")
        }
        return .unavailable("sidebar-conversation-miss")
    }

    private func pressConversation(
        title: String,
        workspaceName: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> Bool {
        guard hasTimeRemaining(before: deadline),
              let container = projectContainer(named: workspaceName, in: root, before: deadline),
              let taskItem = taskItem(titled: title, in: container, before: deadline),
              hasTimeRemaining(before: deadline) else {
            return false
        }
        return AXUIElementPerformAction(taskItem, kAXPressAction as CFString) == .success
    }

    private func waitUntilConversationIsActive(
        title: String,
        workspaceName: String,
        application: NSRunningApplication,
        before deadline: TimeInterval
    ) -> Bool {
        // Electron temporarily removes its AXWindow while navigating between
        // conversations. Reacquire the window and DOM nodes on every poll;
        // stale Chromium elements can otherwise make a completed transition
        // look like a miss or, worse, a false success.
        for attempt in 0..<60 where hasTimeRemaining(before: deadline) {
            if let window = firstWindow(of: application),
               let container = projectContainer(named: workspaceName, in: window, before: deadline),
               let item = taskItem(titled: title, in: container, before: deadline),
               domClasses(of: item).contains("bg-selected"),
               hasConversationHeading(title, in: window, before: deadline) {
                return true
            }
            if attempt < 59 {
                sleep(0.05, before: deadline)
            }
        }
        return false
    }

    private func ensureProjectsView(in root: AXUIElement, before deadline: TimeInterval) {
        for element in descendants(of: root, before: deadline) {
            guard displayedText(of: element) == "项目" || displayedText(of: element) == "Projects",
                  let tab = nearestAncestor(
                      of: element,
                      maximumLevels: 3,
                      before: deadline,
                      matching: { candidate in
                          let role = copyStringValue(
                              of: candidate,
                              attribute: kAXRoleAttribute as CFString
                          )
                          return (role == "AXTab" || role == "AXRadioButton")
                              && hasAction(kAXPressAction as CFString, on: candidate)
                      }
                  ) else {
                continue
            }
            if hasTimeRemaining(before: deadline),
               copyBoolValue(of: tab, attribute: kAXSelectedAttribute as CFString) != true {
                _ = AXUIElementPerformAction(tab, kAXPressAction as CFString)
                sleep(0.08, before: deadline)
            }
            return
        }
    }

    private func expandProjectIfNeeded(
        named workspaceName: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) {
        guard hasTimeRemaining(before: deadline),
              !workspaceName.isEmpty,
              let button = projectButton(named: workspaceName, in: root, before: deadline),
              copyBoolValue(of: button, attribute: kAXExpandedAttribute as CFString) != true else {
            return
        }
        if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
            sleep(0.08, before: deadline)
        }
    }

    private func pressShowMore(
        forProjectNamed workspaceName: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> Bool {
        guard hasTimeRemaining(before: deadline),
              let projectContainer = projectContainer(
                named: workspaceName,
                in: root,
                before: deadline
              ) else {
            return false
        }

        for element in descendants(of: projectContainer, before: deadline) {
            guard displayedText(of: element) == "显示更多" || displayedText(of: element) == "Show more",
                  let pressable = nearestPressableAncestor(
                    of: element,
                    maximumLevels: 2,
                    before: deadline
                  ),
                  hasTimeRemaining(before: deadline) else {
                continue
            }
            return AXUIElementPerformAction(pressable, kAXPressAction as CFString) == .success
        }
        return false
    }

    private func projectButton(
        named workspaceName: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        for element in descendants(of: root, before: deadline)
        where displayedText(of: element) == workspaceName {
            if let button = nearestAncestor(
                of: element,
                maximumLevels: 3,
                before: deadline,
                matching: { candidate in
                    copyStringValue(of: candidate, attribute: kAXRoleAttribute as CFString) == "AXButton"
                        && hasAction(kAXPressAction as CFString, on: candidate)
                }
            ) {
                return button
            }
        }
        return nil
    }

    private func projectContainer(
        named workspaceName: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        guard let button = projectButton(named: workspaceName, in: root, before: deadline) else {
            return nil
        }
        return nearestAncestor(of: button, maximumLevels: 3, before: deadline) { candidate in
            domClasses(of: candidate).contains("space-y-2")
        }
    }

    private func taskItem(
        titled title: String,
        in projectContainer: AXUIElement,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        for element in descendants(of: projectContainer, before: deadline)
        where copyStringValue(of: element, attribute: kAXRoleAttribute as CFString) == "AXStaticText"
            && displayedText(of: element) == title {
            if let item = nearestAncestor(
                of: element,
                maximumLevels: 4,
                before: deadline,
                matching: { candidate in
                    domClasses(of: candidate).contains("group/task-item")
                        && hasAction(kAXPressAction as CFString, on: candidate)
                }
            ) {
                return item
            }
        }
        return nil
    }

    private func hasConversationHeading(
        _ title: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> Bool {
        descendants(of: root, before: deadline).contains { element in
            guard copyStringValue(of: element, attribute: kAXRoleAttribute as CFString) == "AXHeading",
                  displayedText(of: element) == title else {
                return false
            }
            return nearestAncestor(of: element, maximumLevels: 4, before: deadline) { candidate in
                copyStringValue(of: candidate, attribute: kAXDOMIdentifierAttribute as CFString)
                    == "conversation"
            } != nil
        }
    }

    private func domClasses(of element: AXUIElement) -> [String] {
        copyStringArrayValue(of: element, attribute: "AXDOMClassList" as CFString) ?? []
    }

    private func descendants(of root: AXUIElement, before deadline: TimeInterval) -> [AXUIElement] {
        let maximumNodes = 5_000
        let maximumDepth = 64
        var result: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var nextIndex = 0

        while nextIndex < queue.count,
              result.count < maximumNodes,
              hasTimeRemaining(before: deadline) {
            let (element, depth) = queue[nextIndex]
            nextIndex += 1
            result.append(element)
            guard depth < maximumDepth,
                  let children = copyElementArrayValue(
                    of: element,
                    attribute: kAXChildrenAttribute as CFString
                  ) else {
                continue
            }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return result
    }

    private func nearestPressableAncestor(
        of element: AXUIElement,
        maximumLevels: Int,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        nearestAncestor(of: element, maximumLevels: maximumLevels, before: deadline) { candidate in
            hasAction(kAXPressAction as CFString, on: candidate)
        }
    }

    private func nearestAncestor(
        of element: AXUIElement,
        maximumLevels: Int,
        before deadline: TimeInterval,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var current = element
        for _ in 0..<maximumLevels where hasTimeRemaining(before: deadline) {
            guard let parent = copyElementValue(
                of: current,
                attribute: kAXParentAttribute as CFString
            ) else {
                return nil
            }
            if predicate(parent) {
                return parent
            }
            current = parent
        }
        return nil
    }

    private func hasAction(_ action: CFString, on element: AXUIElement) -> Bool {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let actions = value as? [String] else {
            return false
        }
        return actions.contains(action as String)
    }

    private func displayedText(of element: AXUIElement) -> String? {
        let text = copyStringValue(of: element, attribute: kAXValueAttribute as CFString)
            ?? copyStringValue(of: element, attribute: kAXTitleAttribute as CFString)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyStringValue(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyBoolValue(of element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func copyStringArrayValue(of element: AXUIElement, attribute: CFString) -> [String]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? [String]
    }

    private func copyElementValue(of element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copyElementArrayValue(of element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func raise(window: AXUIElement, before deadline: TimeInterval) -> Bool {
        guard hasTimeRemaining(before: deadline) else { return false }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return hasTimeRemaining(before: deadline)
    }

    private func waitForWindow(
        of application: NSRunningApplication,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        for attempt in 0..<30 where hasTimeRemaining(before: deadline) {
            if let window = firstWindow(of: application) {
                return window
            }
            if attempt < 29 {
                sleep(0.05, before: deadline)
            }
        }
        return nil
    }

    private func hasTimeRemaining(before deadline: TimeInterval) -> Bool {
        clock() < deadline
    }

    private func sleep(_ interval: TimeInterval, before deadline: TimeInterval) {
        let remaining = deadline - clock()
        guard remaining > 0 else { return }
        sleeper(min(interval, remaining))
    }

    private func firstWindow(of application: NSRunningApplication) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        return copyElementArrayValue(
            of: applicationElement,
            attribute: kAXWindowsAttribute as CFString
        )?.first
    }
}
