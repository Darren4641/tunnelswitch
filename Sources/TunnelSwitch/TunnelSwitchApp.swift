import AppKit
import SwiftUI

@main
struct TunnelSwitchApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("터널 스위처", id: "main") {
            MainView().environmentObject(store)
        }
        .defaultSize(width: 600, height: 520)

        MenuBarExtra {
            MenuBarPanel().environmentObject(store)
        } label: {
            if let g = store.runningGroup {
                Image(systemName: store.hasProblem ? "exclamationmark.triangle.fill" : "point.3.filled.connected.trianglepath.dotted")
                Text(g.label)
            } else {
                Image(systemName: "point.3.connected.trianglepath.dotted")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// 메뉴바에서 여는 간단한 패널: 켜기/끄기와 상태만 보여준다. 등록·편집은 메인 창에서 한다.
struct MenuBarPanel: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.snapshot?.groups.isEmpty == true {
                Text("그룹이 없습니다. 창을 열어 그룹을 만드세요.").foregroundStyle(.secondary)
            }
            ForEach(store.snapshot?.groups ?? []) { g in
                GroupHeader(group: g, compact: true)
                ForEach(g.tunnels) { t in
                    TunnelRow(tunnel: t,
                              onToggle: { store.setTunnel(t.config.name, in: g.key, on: $0) },
                              onOpen: { store.openInBrowser(t.config.name, in: g.key) },
                              compact: true)
                }
            }
            Divider()
            HStack {
                Button("창 열기") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("앱 종료") { NSApp.terminate(nil) }
                    .help("앱만 종료합니다. 켜진 터널은 백그라운드에서 계속 동작합니다.")
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}
