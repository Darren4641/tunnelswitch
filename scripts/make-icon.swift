// 앱 아이콘 원본(1024×1024 PNG)을 그린다. 사용: swift scripts/make-icon.swift <출력.png> [시안]
// 은은한 그라데이션 바탕 위에 굵은 선으로 그린 터널 입구 기호 하나와, 연결됨을 뜻하는 초록 점.
import AppKit

let size: CGFloat = 1024
let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon.png"
let variant = args.count > 2 ? args[2] : "dark"

struct Palette { var top: UInt32; var bottom: UInt32; var glyph: UInt32; var dot: UInt32 }
let palettes: [String: Palette] = [
    "dark":  Palette(top: 0x2B3446, bottom: 0x0E121B, glyph: 0xFFFFFF, dot: 0x34D399),
    "blue":  Palette(top: 0x4F8BFF, bottom: 0x3B3FD8, glyph: 0xFFFFFF, dot: 0x4ADE80),
    "light": Palette(top: 0xFFFFFF, bottom: 0xE3E8F0, glyph: 0x1E2533, dot: 0x10B981),
]
let pal = palettes[variant] ?? palettes["dark"]!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 바탕: macOS 아이콘 격자(본체 824px, 모서리 185px)
let bodyPath = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.28))
ctx.addPath(bodyPath)
ctx.setFillColor(color(pal.bottom))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [color(pal.top), color(pal.bottom)] as CFArray, locations: nil)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// 터널 기호: 바깥 아치(입구) + 안쪽 아치(깊이) + 바닥선 (선 기호 스타일)
let cx: CGFloat = 495, line: CGFloat = 46  // 오른쪽 연결 점까지 포함해 가운데에 오도록 조금 왼쪽
let groundY: CGFloat = 300, archY: CGFloat = 490   // 아치가 반원으로 바뀌는 높이
let outerR: CGFloat = 230, innerR: CGFloat = 108
// 연결 점은 바닥선 오른쪽 끝에 붙는다
let dot = CGPoint(x: cx + outerR + 75, y: groundY)
let dotR: CGFloat = 58, gap: CGFloat = 22

// 기호는 별도 레이어에 그리고, 점 자리를 원형으로 뚫어 바탕이 비치게 한다
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

ctx.setStrokeColor(color(pal.glyph))
ctx.setLineWidth(line)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

func arch(_ r: CGFloat, top: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx - r, y: groundY))
    p.addLine(to: CGPoint(x: cx - r, y: top))
    p.addArc(center: CGPoint(x: cx, y: top), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
    p.addLine(to: CGPoint(x: cx + r, y: groundY))
    return p
}
ctx.addPath(arch(outerR, top: archY))
ctx.strokePath()
ctx.addPath(arch(innerR, top: archY - 40))
ctx.strokePath()

// 바닥선: 아치 양옆으로 뻗어 오른쪽 끝이 연결 점에 닿는다
ctx.move(to: CGPoint(x: cx - outerR - 75, y: groundY))
ctx.addLine(to: CGPoint(x: dot.x, y: groundY))
ctx.strokePath()

let cut = dotR + gap
ctx.setBlendMode(.clear)
ctx.fillEllipse(in: CGRect(x: dot.x - cut, y: dot.y - cut, width: cut * 2, height: cut * 2))
ctx.setBlendMode(.normal)
ctx.endTransparencyLayer()

// 연결 점: 바닥선 오른쪽 끝
ctx.setFillColor(color(pal.dot))
ctx.fillEllipse(in: CGRect(x: dot.x - dotR, y: dot.y - dotR, width: dotR * 2, height: dotR * 2))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("그림: \(out)")
