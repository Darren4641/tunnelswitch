import Foundation

/// `tunsw status --json` 응답
struct Snapshot: Decodable {
    var running: String?
    var groups: [TunnelGroup]
    var log: String
}

/// `tunsw terminals --json` 응답: SSH 접속에 쓸 수 있는 설치된 터미널 앱
struct TerminalApp: Decodable, Identifiable {
    var id: String
    var name: String
}

/// `tunsw update --check --json` 응답
struct UpdateInfo: Decodable {
    var current: String
    var latest: String
    /// 설치 후 새로 올라온 커밋 제목 (최신 순). 비어 있으면 최신 버전
    var commits: [String]
    /// 마지막 업데이트 상태: running / failed / done
    var state: String?
    var message: String?

    var available: Bool { !commits.isEmpty }

    /// `tunsw update --status` 응답
    struct Status: Decodable {
        var state: String?
        var message: String?
    }
}

struct TunnelGroup: Decodable, Identifiable {
    var key: String
    var label: String
    var tunnels: [Tunnel]
    var id: String { key }
}

struct Tunnel: Decodable, Identifiable {
    var config: TunnelConfig
    var target: String
    var via: String
    /// web 터널을 브라우저로 열 주소 (다른 방식은 nil)
    var url: String?
    var enabled: Bool
    var state: String
    var restarts: Int
    var last_error: String?
    var id: String { config.name }

    /// SSH 접속(shell) 항목. 포워딩이 없어 켜고 끄지 않고 터미널로 접속만 한다.
    var isShell: Bool { config.type == TunnelType.shell.rawValue }
}

struct TunnelConfig: Codable {
    var name: String
    var type: String
    /// shell(SSH 접속)에는 없다
    var local_port: Int?
    var remote_port: Int?
    var remote_host: String?
    var instance_id: String?
    var profile: String?
    var os_user: String?
    var region: String?
    var eice_id: String?
    var host: String?
    var user: String?
    var ssh_port: Int?
    var key: String?
    var private_ip: String?
    var auth: String?
    var password: String?
    var scheme: String?
}

enum TunnelType: String, CaseIterable, Identifiable {
    case eic, ssh, eicDirect = "eic-direct", web, shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eic: return "EIC → 배스천"
        case .ssh: return "SSH(pem) → 배스천"
        case .eicDirect: return "EIC 직접"
        case .web: return "웹 서비스"
        case .shell: return "SSH 접속"
        }
    }

    /// SSH 로 접속하는 방식 (pem 또는 비밀번호 인증)
    var usesSSH: Bool { self == .ssh || self == .web || self == .shell }

    var help: String {
        switch self {
        case .eic: return "EIC Endpoint 로 배스천 EC2 에 SSH 한 뒤 RDS 로 포워딩합니다."
        case .ssh: return "pem 키로 공인 IP 배스천에 SSH 한 뒤 RDS 로 포워딩합니다."
        case .eicDirect: return "EIC open-tunnel 로 VPC 내부 IP:포트에 직접 연결합니다."
        case .web: return "SSH 서버를 거쳐 ArgoCD·Jenkins 같은 웹 서비스를 localhost 로 열고 브라우저로 띄웁니다."
        case .shell: return "터널 없이 ssh user@host 로 접속합니다. 목록의 \"접속\" 버튼을 누르면 터미널이 열립니다."
        }
    }
}

enum SSHAuth: String, CaseIterable, Identifiable {
    case key, password

    var id: String { rawValue }

    var title: String {
        switch self {
        case .key: return "pem 키"
        case .password: return "비밀번호"
        }
    }
}

/// 편집 폼 입력값. 문자열로 들고 있다가 저장할 때 JSON 으로 바꾼다. 검증은 tunsw 가 한다.
struct Draft {
    var group = ""
    var original: String?
    var name = ""
    var type = TunnelType.eic
    var localPort = ""
    var remoteHost = ""
    var remotePort = "3306"
    var instanceId = ""
    var profile = ""
    var osUser = "ec2-user"
    var region = ""
    var eiceId = ""
    var host = ""
    var user = "ec2-user"
    var sshPort = "22"
    var key = ""
    var privateIp = ""
    var auth = SSHAuth.key
    var password = ""
    var scheme = "http"

    init(group: String) { self.group = group }

    init(group: String, config c: TunnelConfig) {
        self.group = group
        original = c.name
        name = c.name
        type = TunnelType(rawValue: c.type) ?? .eic
        localPort = c.local_port.map(String.init) ?? ""
        remotePort = c.remote_port.map(String.init) ?? "3306"
        remoteHost = c.remote_host ?? ""
        instanceId = c.instance_id ?? ""
        profile = c.profile ?? ""
        osUser = c.os_user ?? "ec2-user"
        region = c.region ?? ""
        eiceId = c.eice_id ?? ""
        host = c.host ?? ""
        user = c.user ?? "ec2-user"
        sshPort = c.ssh_port.map(String.init) ?? "22"
        key = c.key ?? ""
        privateIp = c.private_ip ?? ""
        auth = SSHAuth(rawValue: c.auth ?? "") ?? .key
        password = c.password ?? ""
        scheme = c.scheme ?? "http"
    }

    /// 선택한 방식에 해당하는 필드만 담는다.
    func json() -> String {
        func s(_ v: String) -> Any { v.trimmingCharacters(in: .whitespaces) }
        func n(_ v: String) -> Any { Int(v.trimmingCharacters(in: .whitespaces)) ?? v }
        var d: [String: Any] = ["name": s(name), "type": type.rawValue]
        if type != .shell {
            d.merge(["local_port": n(localPort), "remote_port": n(remotePort)]) { $1 }
        }
        switch type {
        case .eic:
            d.merge(["instance_id": s(instanceId), "profile": s(profile), "os_user": s(osUser),
                     "region": s(region), "eice_id": s(eiceId), "remote_host": s(remoteHost)]) { $1 }
        case .ssh, .web, .shell:
            d.merge(["host": s(host), "user": s(user), "ssh_port": n(sshPort), "auth": auth.rawValue]) { $1 }
            if type != .shell { d["remote_host"] = s(remoteHost) }
            // 비밀번호는 앞뒤 공백도 그대로 둔다
            if auth == .key { d["key"] = s(key) } else { d["password"] = password }
            if type == .web { d["scheme"] = scheme }
        case .eicDirect:
            d.merge(["eice_id": s(eiceId), "profile": s(profile), "region": s(region),
                     "private_ip": s(privateIp)]) { $1 }
        }
        let data = try! JSONSerialization.data(withJSONObject: d)
        return String(decoding: data, as: UTF8.self)
    }
}
