import AppKit
import SwiftUI

struct EditorView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let d = $store.draft
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("그룹", selection: d.group) {
                        ForEach(store.snapshot?.groups ?? []) { g in Text(g.label).tag(g.key) }
                    }
                    .disabled(store.draft.original != nil)
                    TextField("이름", text: d.name, prompt: Text("dev-rds"))
                    Picker("방식", selection: d.type) {
                        ForEach(TunnelType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(store.draft.type.help).font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text(store.draft.original == nil ? "터널 등록" : "터널 편집").font(.headline)
                }

                Section(store.draft.type == .shell ? "접속" : "경유") {
                    switch store.draft.type {
                    case .eic:
                        TextField("배스천 인스턴스 ID", text: d.instanceId, prompt: Text("i-0123456789abcdef0"))
                        TextField("AWS 프로파일", text: d.profile, prompt: Text("my-aws-profile"))
                        TextField("OS 유저", text: d.osUser)
                        TextField("리전 (선택)", text: d.region, prompt: Text("프로파일 설정 사용"))
                        TextField("EIC Endpoint ID (선택)", text: d.eiceId, prompt: Text("자동 탐색"))
                    case .ssh, .web, .shell:
                        TextField(store.draft.type == .ssh ? "배스천 호스트/IP" : "SSH 서버 호스트/IP",
                                  text: d.host, prompt: Text("43.201.0.1"))
                        TextField("유저", text: d.user)
                        TextField("SSH 포트", text: d.sshPort)
                        Picker("인증", selection: d.auth) {
                            ForEach(SSHAuth.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if store.draft.auth == .key {
                            HStack {
                                TextField("pem 키", text: d.key, prompt: Text("~/keys/bastion.pem"))
                                Button("선택…", action: pickKey)
                            }
                        } else {
                            SecureField("비밀번호", text: d.password)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Button("연결 테스트") { store.testConnection() }
                                .disabled(store.testing)
                                .help("입력한 값으로 SSH 로그인만 해 보고 끊습니다 (저장하지 않음)")
                            if store.testing {
                                ProgressView().controlSize(.small)
                            } else if let r = store.testResult {
                                Label(r.message, systemImage: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(r.ok ? .green : .red)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        }
                    case .eicDirect:
                        TextField("EIC Endpoint ID", text: d.eiceId, prompt: Text("eice-0123456789abcdef0"))
                        TextField("AWS 프로파일", text: d.profile, prompt: Text("my-aws-profile"))
                        TextField("리전 (선택)", text: d.region, prompt: Text("프로파일 설정 사용"))
                    }
                }

                if store.draft.type != .shell {
                Section("대상") {
                    if store.draft.type == .eicDirect {
                        TextField("내부 IP", text: d.privateIp, prompt: Text("10.0.1.23"))
                        TextField("포트", text: d.remotePort)
                    } else if store.draft.type == .web {
                        TextField("서비스 호스트", text: d.remoteHost,
                                  prompt: Text("127.0.0.1 (SSH 서버 자신)"))
                        TextField("서비스 포트", text: d.remotePort)
                        Picker("프로토콜", selection: d.scheme) {
                            Text("http").tag("http")
                            Text("https").tag("https")
                        }
                        .pickerStyle(.segmented)
                    } else {
                        TextField("RDS 엔드포인트", text: d.remoteHost,
                                  prompt: Text("xxx.cluster-xxxx.ap-northeast-2.rds.amazonaws.com"))
                        TextField("RDS 포트", text: d.remotePort)
                    }
                    if store.draft.type == .web {
                        TextField("로컬 포트 (브라우저)", text: d.localPort, prompt: Text("18080"))
                        if let port = Int(store.draft.localPort) {
                            Text("브라우저: \(store.draft.scheme)://localhost:\(String(port))")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } else {
                        TextField("로컬 포트 (DataGrip)", text: d.localPort, prompt: Text("13306"))
                    }
                }
                }

                if store.draft.original != nil, isEnabled {
                    Text("켜져 있는 터널입니다. 저장하면 이 터널만 다시 연결됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let err = store.formError {
                    Text(err).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .onChange(of: store.draft.type) { old, new in
                // 기본 포트를 그대로 둔 채 방식을 바꾸면 그 방식의 기본 포트로 바꿔 준다
                if new == .web, store.draft.remotePort == "3306" { store.draft.remotePort = "8080" }
                if old == .web, store.draft.remotePort == "8080" { store.draft.remotePort = "3306" }
            }

            HStack {
                Spacer()
                Button("취소") { store.showEditor = false }.keyboardShortcut(.cancelAction)
                Button(store.draft.original == nil ? "등록" : "저장") { store.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.busy)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 540, height: 600)
    }

    private var isEnabled: Bool {
        store.snapshot?.groups.first { $0.key == store.draft.group }?
            .tunnels.first { $0.config.name == store.draft.original }?.enabled ?? false
    }

    private func pickKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            store.draft.key = url.path
        }
    }
}
