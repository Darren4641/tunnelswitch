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
    /// 편집 폼의 연결 테스트: 진행 중이면 끝나는 시각, 끝나면 결과 (성공 여부, 메시지)
    @Published var testDeadline: Date?
    @Published var testResult: (ok: Bool, message: String)?
    var testing: Bool { testDeadline != nil }
    /// 연결 테스트 전체 제한 시간(초). 엔진에 --timeout 으로 넘긴다.
    let testTimeout = 30
    private var testProcess: Process?
    /// 취소했거나 새로 시작한 테스트의 늦게 온 결과를 버리기 위한 번호
    private var testID = 0
    @Published var update: UpdateInfo?
    @Published var updating = false
    @Published var updateError: String?
    /// SSH 접속을 열 수 있는 설치된 터미널 앱 (기본으로 고를 순서대로)
    @Published var terminals: [TerminalApp] = []
    /// 고른 터미널 앱 id. 처음에는 설치된 것 중 첫 번째 (iTerm2 등이 macOS 터미널보다 앞)
    @Published var terminal = UserDefaults.standard.string(forKey: "terminal") ?? "" {
        didSet { UserDefaults.standard.set(terminal, forKey: "terminal") }
    }

    private var timer: Timer?
    private var updateTimer: Timer?
    private var refreshing = false

    /// "나중에" 를 누른 버전. 같은 버전은 다시 묻지 않는다.
    private let declinedKey = "declinedUpdate"

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        loadTerminals()
        checkForUpdate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdate() }
        }
    }

    var running: String? { snapshot?.running }

    var runningGroup: TunnelGroup? { snapshot?.groups.first { $0.key == running } }

    var selectedGroup: TunnelGroup? {
        snapshot?.groups.first { $0.key == selected } ?? snapshot?.groups.first
    }

    var hasProblem: Bool {
        runningGroup?.tunnels.contains { $0.enabled && $0.state != "connected" } ?? false
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

    /// SSH 접속 항목으로 고른 터미널 앱 새 창에서 접속한다.
    func connect(_ name: String, in group: String) {
        perform(["ssh", "--window", "--terminal", terminal, group, name])
    }

    var terminalName: String {
        terminals.first { $0.id == terminal }?.name ?? "터미널"
    }

    private func loadTerminals() {
        Task.detached {
            let r = Engine.run(["terminals", "--json"])
            let list = (try? JSONDecoder().decode([TerminalApp].self, from: Data(r.out.utf8))) ?? []
            await MainActor.run {
                self.terminals = list
                if !list.contains(where: { $0.id == self.terminal }), let first = list.first {
                    self.terminal = first.id
                }
            }
        }
    }

    func beginEdit(_ draft: Draft) {
        self.draft = draft
        formError = nil
        cancelTest()
        testResult = nil
        showEditor = true
    }

    /// 편집 중인 값으로 SSH 로그인만 해 본다 (저장하지 않음).
    func testConnection() {
        cancelTest()
        testID += 1
        let id = testID
        testDeadline = Date().addingTimeInterval(TimeInterval(testTimeout))
        testResult = nil
        let args = ["test", "--timeout", String(testTimeout), "--json", draft.json()]
        Task.detached {
            let r = Engine.run(args) { p in
                Task { @MainActor in if self.testID == id { self.testProcess = p } }
            }
            await MainActor.run {
                guard self.testID == id else { return }
                self.testDeadline = nil
                self.testProcess = nil
                self.testResult = (r.code == 0, r.message)
            }
        }
    }

    /// 진행 중인 연결 테스트를 끊는다. 엔진이 SIGTERM 을 받으면 ssh 도 함께 종료한다.
    func cancelTest(showResult: Bool = false) {
        guard testing else { return }
        testID += 1
        testProcess?.terminate()
        testProcess = nil
        testDeadline = nil
        if showResult { testResult = (false, "취소했습니다.") }
    }

    func save() {
        formError = nil
        var args = ["add", draft.group, "--json", draft.json()]
        if let original = draft.original { args += ["--replace", original] }
        let group = draft.group
        perform(args, onSuccess: {
            self.selected = group
            self.cancelTest()
            self.showEditor = false
        }, onFailure: { self.formError = $0 })
    }

    func delete(_ tunnel: Tunnel, in group: String) {
        let alert = NSAlert()
        alert.messageText = "'\(tunnel.config.name)' 터널을 삭제할까요?"
        alert.informativeText = tunnel.config.local_port.map { "127.0.0.1:\($0) → \(tunnel.target)" } ?? tunnel.target
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

    // MARK: 업데이트

    /// 새 버전이 있는지 확인한다. 새 버전이면 업데이트할지 묻는다 (나중에 를 누른 버전은 묻지 않음).
    /// manual: 사용자가 직접 확인한 경우. 최신이거나 확인에 실패해도 알려 주고, 거절했던 버전도 다시 묻는다.
    func checkForUpdate(manual: Bool = false) {
        guard !updating else { return }
        Task.detached {
            let r = Engine.run(["update", "--check", "--json"])
            await MainActor.run {
                guard r.code == 0,
                      let info = try? JSONDecoder().decode(UpdateInfo.self, from: Data(r.out.utf8)) else {
                    // 자동 확인은 오프라인 등으로 실패해도 조용히 넘어간다
                    if manual { self.updateError = "업데이트 확인 실패: \(r.message)" }
                    return
                }
                self.update = info
                if !info.available {
                    if manual { self.inform("최신 버전입니다", "설치된 버전: \(info.current)") }
                    return
                }
                if manual || UserDefaults.standard.string(forKey: self.declinedKey) != info.latest {
                    self.askToUpdate(info)
                }
            }
        }
    }

    private func askToUpdate(_ info: UpdateInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "새 버전이 있습니다. 업데이트할까요?"
        let list = info.commits.prefix(8).map { "• \($0)" }.joined(separator: "\n")
        let more = info.commits.count > 8 ? "\n외 \(info.commits.count - 8)개" : ""
        alert.informativeText = "\(info.current) → \(info.latest)\n\n\(list)\(more)\n\n"
            + "앱을 다시 빌드해 설치한 뒤 다시 엽니다. 켜진 터널은 끊기지 않습니다."
        alert.addButton(withTitle: "업데이트")
        alert.addButton(withTitle: "나중에")
        if alert.runModal() == .alertFirstButtonReturn {
            startUpdate()
        } else {
            UserDefaults.standard.set(info.latest, forKey: declinedKey)
        }
    }

    /// 백그라운드에서 git pull + install.sh 를 실행한다. 성공하면 install.sh 가 앱을 종료하고 다시 띄우고,
    /// 실패하면 이 앱이 살아 있으므로 상태 파일을 읽어 이유를 보여 준다.
    func startUpdate() {
        updating = true
        updateError = nil
        Task.detached {
            let r = Engine.run(["update", "--background"])
            guard r.code == 0 else {
                await MainActor.run {
                    self.updating = false
                    self.updateError = r.message
                }
                return
            }
            while true {
                try? await Task.sleep(for: .seconds(2))
                let s = Engine.run(["update", "--status"])
                let status = try? JSONDecoder().decode(UpdateInfo.Status.self, from: Data(s.out.utf8))
                if status?.state == "running" { continue }
                await MainActor.run {
                    self.updating = false
                    if status?.state == "failed" {
                        self.updateError = status?.message ?? "업데이트에 실패했습니다."
                    }
                }
                return
            }
        }
    }

    private func inform(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    func openLog() {
        guard let log = snapshot?.log, FileManager.default.fileExists(atPath: log) else {
            error = "아직 로그가 없습니다."
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: log))
    }
}
