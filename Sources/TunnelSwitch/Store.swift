import AppKit
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var selected: String?
    @Published var busy = false
    @Published var error: String?
    @Published var draft = Draft(group: "")
    @Published var formError: String?
    @Published var showEditor = false

    private var timer: Timer?
    private var refreshing = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var running: String? { snapshot?.running }

    var runningGroup: TunnelGroup? { snapshot?.groups.first { $0.key == running } }

    var selectedGroup: TunnelGroup? {
        snapshot?.groups.first { $0.key == selected } ?? snapshot?.groups.first
    }

    var hasProblem: Bool {
        runningGroup?.tunnels.contains { $0.state != "connected" } ?? false
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task.detached {
            let r = Engine.run(["status", "--json"])
            await MainActor.run {
                self.refreshing = false
                guard r.code == 0,
                      let snap = try? JSONDecoder().decode(Snapshot.self, from: Data(r.out.utf8)) else {
                    self.error = r.message.isEmpty ? "상태를 읽지 못했습니다." : r.message
                    return
                }
                self.snapshot = snap
                if self.selected == nil { self.selected = snap.running ?? snap.groups.first?.key }
            }
        }
    }

    /// 엔진을 백그라운드에서 실행하고, 끝나면 상태를 다시 읽는다.
    func perform(_ args: [String], onSuccess: (() -> Void)? = nil, onFailure: ((String) -> Void)? = nil) {
        busy = true
        error = nil
        Task.detached {
            let r = Engine.run(args)
            await MainActor.run {
                self.busy = false
                if r.code == 0 {
                    onSuccess?()
                } else if let onFailure {
                    onFailure(r.message)
                } else {
                    self.error = r.message
                }
                self.refresh()
            }
        }
    }

    /// 터널 하나 켜기/끄기. 다른 그룹이 켜져 있으면 그 그룹은 꺼진다.
    func setTunnel(_ name: String, in group: String, on: Bool) {
        perform([on ? "on" : "off", group, name])
    }

    /// 그룹 전체 켜기/끄기
    func setAll(_ group: String, on: Bool) {
        perform([on ? "on" : "off", group])
    }

    /// web 터널을 브라우저로 연다. 꺼져 있으면 켜고 연결될 때까지 기다린다 (다른 그룹은 꺼짐).
    func openInBrowser(_ name: String, in group: String) {
        perform(["open", group, name])
    }

    func beginEdit(_ draft: Draft) {
        self.draft = draft
        formError = nil
        showEditor = true
    }

    func save() {
        formError = nil
        var args = ["add", draft.group, "--json", draft.json()]
        if let original = draft.original { args += ["--replace", original] }
        let group = draft.group
        perform(args, onSuccess: {
            self.selected = group
            self.showEditor = false
        }, onFailure: { self.formError = $0 })
    }

    func delete(_ tunnel: Tunnel, in group: String) {
        let alert = NSAlert()
        alert.messageText = "'\(tunnel.config.name)' 터널을 삭제할까요?"
        alert.informativeText = "127.0.0.1:\(tunnel.config.local_port) → \(tunnel.target)"
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(["remove", group, tunnel.config.name])
    }

    // MARK: 그룹

    func addGroup() {
        guard let name = promptName(title: "새 그룹", message: "예: 회사 이름, AWS 계정", initial: "") else { return }
        perform(["group-add", name]) { self.selected = name }
    }

    func renameGroup(_ group: TunnelGroup) {
        guard let name = promptName(title: "그룹 이름 변경", message: "", initial: group.label),
              name != group.label else { return }
        perform(["group-rename", group.key, name])
    }

    func deleteGroup(_ group: TunnelGroup) {
        let alert = NSAlert()
        alert.messageText = "'\(group.label)' 그룹을 삭제할까요?"
        var info = group.tunnels.isEmpty ? "등록된 터널이 없습니다." : "등록된 터널 \(group.tunnels.count)개도 함께 삭제됩니다."
        if group.key == running { info += "\n켜져 있는 터널은 모두 꺼집니다." }
        alert.informativeText = info
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(["group-remove", group.key, "--force"]) {
            if self.selected == group.key { self.selected = nil }
        }
    }

    /// 텍스트 입력 대화상자. 취소하거나 비워 두면 nil
    private func promptName(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        field.placeholderString = "그룹 이름"
        alert.accessoryView = field
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    func openLog() {
        guard let log = snapshot?.log, FileManager.default.fileExists(atPath: log) else {
            error = "아직 로그가 없습니다."
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: log))
    }
}
