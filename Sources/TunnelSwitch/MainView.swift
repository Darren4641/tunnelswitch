import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let groups = store.snapshot?.groups {
                if groups.isEmpty {
                    NoGroupsView()
                } else {
                    HStack {
                        Picker("", selection: Binding(
                            get: { store.selectedGroup?.key ?? "" },
                            set: { store.selected = $0 })) {
                            ForEach(groups) { g in
                                Text(g.key == store.running ? "● \(g.label)" : g.label).tag(g.key)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Button { store.addGroup() } label: { Image(systemName: "plus") }
                            .help("그룹 추가")
                            .disabled(store.busy)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }

            if let group = store.selectedGroup {
                GroupHeader(group: group)
                TunnelList(group: group)
            }
            if let error = store.error {
                Banner(text: error, color: .red) {
                    Button("닫기") { store.error = nil }
                }
            }

            HStack {
                Button {
                    if let g = store.selectedGroup { store.beginEdit(Draft(group: g.key)) }
                } label: { Label("터널 추가", systemImage: "plus") }
                .keyboardShortcut("n")
                .disabled(store.selectedGroup == nil)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button("로그 보기") { store.openLog() }
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 440)
        .sheet(isPresented: $store.showEditor) {
            EditorView().environmentObject(store)
        }
    }
}

/// 그룹 제목, 켜진 개수, 일괄 켜기/끄기. 다른 그룹이 켜져 있으면 켤 때 그 그룹은 꺼진다.
struct GroupHeader: View {
    @EnvironmentObject var store: Store
    let group: TunnelGroup
    var compact = false

    var body: some View {
        let on = group.tunnels.filter(\.enabled)
        let connected = on.filter { $0.state == "connected" }.count
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.label).font(compact ? .headline : .title3.bold())
                if !on.isEmpty {
                    Text("\(on.count)개 켬 · \(connected)개 연결됨")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let other = store.runningGroup, other.key != group.key {
                    Text("켜면 \(other.label) 은 꺼집니다").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !compact {
                Menu {
                    Button("이름 변경…") { store.renameGroup(group) }
                    Button("그룹 삭제…", role: .destructive) { store.deleteGroup(group) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(store.busy)
            }
            Button("모두 켜기") { store.setAll(group.key, on: true) }
                .disabled(store.busy || group.tunnels.isEmpty || on.count == group.tunnels.count)
            Button("모두 끄기") { store.setAll(group.key, on: false) }
                .disabled(store.busy || on.isEmpty)
        }
        .controlSize(compact ? .small : .regular)
    }
}

/// 그룹이 하나도 없을 때의 첫 화면
struct NoGroupsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("그룹을 먼저 만드세요").font(.title3.bold())
            Text("회사나 AWS 계정처럼 함께 켜고 끌 터널 묶음입니다.\n한 번에 한 그룹만 켜집니다.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("그룹 만들기") { store.addGroup() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TunnelList: View {
    @EnvironmentObject var store: Store
    let group: TunnelGroup

    var body: some View {
        if group.tunnels.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.largeTitle).foregroundStyle(.tertiary)
                Text("등록된 터널이 없습니다").foregroundStyle(.secondary)
                Button("터널 추가") { store.beginEdit(Draft(group: group.key)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(group.tunnels) { t in
                        TunnelRow(tunnel: t,
                                  onToggle: { store.setTunnel(t.config.name, in: group.key, on: $0) },
                                  onOpen: { store.openInBrowser(t.config.name, in: group.key) },
                                  onEdit: { store.beginEdit(Draft(group: group.key, config: t.config)) },
                                  onDelete: { store.delete(t, in: group.key) })
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct TunnelRow: View {
    @EnvironmentObject var store: Store
    let tunnel: Tunnel
    let onToggle: (Bool) -> Void
    var onOpen: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var compact = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { tunnel.enabled }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(store.busy)
                .help(tunnel.enabled ? "이 터널 끄기" : "이 터널 켜기")
            Circle().fill(tunnel.stateColor).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(tunnel.config.name).font(.body.bold())
                    Text(tunnel.stateText).font(.caption)
                        .foregroundStyle(tunnel.state == "off" ? Color.secondary : tunnel.stateColor)
                }
                Text("→ \(tunnel.target)").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if !compact {
                    Text(tunnel.via).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                if tunnel.state != "connected", tunnel.state != "off", let err = tunnel.last_error {
                    Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2).textSelection(.enabled)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(String(tunnel.config.local_port), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Text(copied ? "복사됨" : "127.0.0.1:\(String(tunnel.config.local_port))")
                        .font(.system(.callout, design: .monospaced))
                }
                .help("로컬 포트 복사")
                if let url = tunnel.url, let onOpen {
                    Button(action: onOpen) { Label("브라우저", systemImage: "safari") }
                        .controlSize(.small)
                        .disabled(store.busy)
                        .help(tunnel.enabled ? "\(url) 열기" : "터널을 켜고 \(url) 열기")
                }
                if let onEdit, let onDelete {
                    HStack(spacing: 4) {
                        Button(action: onEdit) { Image(systemName: "pencil") }.help("편집")
                        Button(action: onDelete) { Image(systemName: "trash") }.help("삭제")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Tunnel {
    var stateColor: Color {
        switch state {
        case "connected": return .green
        case "connecting": return .orange
        case "port_conflict": return .red
        default: return .gray.opacity(0.5)
        }
    }

    var stateText: String {
        switch state {
        case "connected": return "연결됨"
        case "connecting": return restarts > 0 ? "재연결 중 (\(restarts)회)" : "연결 중"
        case "port_conflict": return "로컬 포트를 다른 프로그램이 사용 중"
        default: return "꺼짐"
        }
    }
}

struct Banner<Action: View>: View {
    let text: String
    let color: Color
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top) {
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
            action().controlSize(.small)
        }
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
