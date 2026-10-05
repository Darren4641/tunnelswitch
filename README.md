# 터널 스위처 (TunnelSwitch)

**배스천 너머의 RDS·Redis, 사내 ArgoCD·Jenkins 를 스위치 하나로 `localhost` 에 붙이는 macOS 앱.**

매번 `ssh -L ...` 이나 `aws ec2-instance-connect open-tunnel ...` 을 외워서 치고, 터미널 탭을 여러 개 띄워 두고,
끊기면 다시 치는 일을 없앤다. 터널을 한 번 등록해 두면 토글로 켜고 끄고, 끊기면 알아서 다시 연결한다.

![터널 스위처 데모: 그룹을 켜면 터널이 연결되고, 하나가 끊기면 자동으로 다시 연결된다](docs/images/demo.gif)

<sub>위 화면은 가짜 서버로 만든 데모 데이터다. "모두 켜기" → 연결 중(주황) → 연결됨(초록) → `redis` 가 끊김 → 자동 재연결.</sub>

## 이런 분께

- 회사·AWS 계정마다 **배스천을 거쳐 DB 에 붙어야** 하는데 명령어가 길고 매번 헷갈린다
- DataGrip·TablePlus 같은 DB 클라이언트에 `127.0.0.1:13306` 만 넣고 쓰고 싶다
- 공인 IP 가 없는 사내 ArgoCD·Jenkins 를 **브라우저로 바로** 열고 싶다
- 터널이 조용히 끊겨서 쿼리가 멈추는 일이 잦다

## 주요 기능

| | |
|---|---|
| **그룹 단위 전환** | 터널을 회사·환경별 그룹으로 묶는다. 한 번에 한 그룹만 켜지고, 다른 그룹을 켜면 기존 그룹은 자동으로 꺼진다 (같은 로컬 포트를 써도 충돌하지 않는다) |
| **자동 재연결** | 백그라운드 데몬이 터널을 유지한다. 끊기면 백오프하며 다시 연결하고, 앱을 종료해도 터널은 살아 있다 |
| **4가지 방식** | EIC → 배스천, SSH(pem) → 배스천, EIC 직접, 웹 서비스 ([아래](#터널-방식) 참고) |
| **상태 표시** | 연결됨·연결 중·재연결 중·포트 충돌을 색으로 보여 주고, 끊긴 이유(ssh 마지막 출력)를 그대로 띄운다 |
| **메뉴바** | 메뉴바 아이콘에 지금 켜진 그룹이 표시되고, 창을 열지 않고도 터널을 켜고 끌 수 있다 |
| **브라우저 열기** | 웹 서비스 터널은 "브라우저" 버튼 한 번으로 켜고, 연결될 때까지 기다린 뒤 연다 |
| **CLI** | 같은 엔진을 `tunsw` 명령으로도 쓴다. 앱과 상태를 공유한다 |

| 연결됨 | 끊김 → 재연결 중 |
|---|---|
| ![모든 터널이 연결된 화면](docs/images/main.png) | ![redis 터널이 끊겨 재연결 중인 화면](docs/images/reconnect.png) |

### 메뉴바에서 바로

창을 열지 않아도 메뉴바 아이콘을 눌러 켜고 끌 수 있다. 메뉴바에는 지금 켜진 그룹 이름이 보이고,
연결이 덜 된 터널이 있으면 아이콘이 ⚠︎ 로 바뀐다. 다른 그룹의 터널을 켜면 기존 그룹은 알아서 꺼진다.

![메뉴바 데모: Acme 운영을 모두 켠 뒤 Acme 스테이징의 jenkins 를 켜면 Acme 운영이 꺼지고 메뉴바 표시가 바뀐다](docs/images/menubar.gif)

## 요구 사항

- macOS 14 이상
- Xcode Command Line Tools (`xcode-select --install`) — Swift 빌드, `python3`, `ssh` 포함
- AWS CLI v2 — EIC 방식을 쓸 때. 터널에 지정하는 AWS 프로파일은 각자의 `~/.aws` 설정을 쓴다

## 설치 / 실행

```bash
git clone https://github.com/Darren4641/tunnelswitch.git
cd tunnelswitch
./scripts/install.sh
```

빌드해서 `~/Applications/TunnelSwitch.app` 에 설치하고 실행한다. 이후에는 Launchpad·Spotlight 에서 "TunnelSwitch"(터널 스위처)로 연다.
터미널용 `tunsw` 명령도 `~/.local/bin/tunsw` 에 링크된다 (예전 이름 `dbtun` 도 같은 명령으로 링크된다).

예전 이름(DB 터널)에서 올라오는 경우 `install.sh` 가 `DBTunnel.app` 을 지우고, 엔진을 처음 실행할 때
`~/.config/dbtunnel` 을 `~/.config/tunnelswitch` 로 옮긴다. 켜져 있던 터널은 새 데몬으로 다시 켜진다.

## 구성

| 경로 | 역할 |
|---|---|
| `engine/tunsw` | 터널 엔진 (Python 표준 라이브러리). 설정 저장, 데몬, 재연결 |
| `Sources/TunnelSwitch/` | SwiftUI 앱. 엔진을 호출해 화면에 보여준다 |
| `scripts/install.sh` | 빌드 + 앱 번들 생성 + 설치 |
| `scripts/make-icon.swift` | 앱 아이콘을 코드로 그린다. `install.sh` 가 호출한다 |

앱 번들에는 `engine/tunsw` 사본이 `Contents/Resources/` 로 들어간다. 엔진을 고치면 `install.sh` 를 다시 실행한다.

## 터널 방식

| 방식 | 경로 |
|---|---|
| EIC → 배스천 | EIC Endpoint 로 배스천 EC2 에 SSH → RDS 로 `-L` 포워딩 |
| SSH(pem) → 배스천 | pem 키로 공인 배스천에 SSH → RDS 로 `-L` 포워딩 |
| EIC 직접 | `aws ec2-instance-connect open-tunnel --private-ip-address` |
| 웹 서비스 | SSH 서버에 접속 → 웹 서비스(기본 `127.0.0.1`, 즉 SSH 서버 자신)로 `-L` 포워딩. 브라우저로 `http(s)://localhost:<로컬 포트>` 를 연다 |

SSH(pem)·웹 서비스 방식은 **pem 키** 또는 **비밀번호**로 인증한다. 비밀번호는 `config.json`(권한 600)에
저장되고, 연결할 때 `SSH_ASKPASS` 로 ssh 에 넘긴다 (OpenSSH 8.4 이상). 비밀번호가 틀리면 한 번만 시도하고 끊은 뒤
백오프하며 다시 시도한다.

웹 서비스 터널은 목록의 "브라우저" 버튼(또는 `tunsw open`)으로 연다. 꺼져 있으면 켜고 연결될 때까지 기다린 뒤 연다.

EIC 방식은 전용 SSH 키(`~/.config/tunnelswitch/eic_ed25519`)를 만들어 연결할 때마다
`send-ssh-public-key` 로 배스천에 올린다. 필요한 권한은 `ec2-instance-connect:SendSSHPublicKey`,
`ec2-instance-connect:OpenTunnel` 이고, EIC Endpoint ID 를 비워 두면 `ec2:DescribeInstanceConnectEndpoints` 도 필요하다.

## 데이터 위치

`~/.config/tunnelswitch/` (환경변수 `TUNSW_HOME` 으로 바꿀 수 있다)

- `config.json` — 등록한 터널 (권한 600)
- `daemon.log` — 연결 로그 (5MB 넘으면 시작할 때 `.log.1` 로 교체)
- `desired.json` — 켜져 있어야 할 터널 목록. 데몬이 1초마다 읽어 실제 상태를 맞춘다
- `daemon.pid`, `status.json` — 실행 상태
- `askpass.sh` — 비밀번호 인증용 `SSH_ASKPASS` 스크립트 (비밀번호는 담지 않고 환경변수에서 읽는다)

## CLI

```bash
tunsw on  <group> [name ...]    # 켜기 (이름 생략 시 그룹 전체). 다른 그룹은 꺼짐
tunsw off <group> [name ...]    # 끄기 (이름 생략 시 그룹 전체)
tunsw open <group> <name>       # 웹 서비스 터널을 브라우저로 열기 (꺼져 있으면 켬)
tunsw status | stop | restart | logs -f
tunsw add | list | remove <group> <name> | edit
tunsw group-add <이름> | group-rename <group> <새 이름> | group-remove <group> [--force]
```

## 라이선스

[MIT](LICENSE)
