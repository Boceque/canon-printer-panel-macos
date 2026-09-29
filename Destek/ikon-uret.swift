// Uygulama ikonunu 1024 px PNG olarak çizer: swift ikon-uret.swift cikti.png
// Yeşil zemin üzerinde beyaz yazıcı, köşede altın renkli kilit (ayar sabitleme).
import AppKit

let boyut = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: boyut, pixelsHigh: boyut,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let renkUzayi = CGColorSpaceCreateDeviceRGB()

func renk(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(red: r, green: g, blue: b, alpha: a).cgColor
}

/// SF Symbol'ü verilen renkle, verilen dikdörtgene sığdırarak çizer.
func sembol(_ ad: String, _ kutu: CGRect, _ c: NSColor, agirlik: NSFont.Weight = .regular) {
    let yapi = NSImage.SymbolConfiguration(pointSize: kutu.height, weight: agirlik)
        .applying(NSImage.SymbolConfiguration(paletteColors: [c]))
    guard let resim = NSImage(systemSymbolName: ad, accessibilityDescription: nil)?.withSymbolConfiguration(yapi) else { return }
    let o = resim.size
    let olcek = min(kutu.width / o.width, kutu.height / o.height)
    let hedef = CGRect(x: kutu.midX - o.width * olcek / 2, y: kutu.midY - o.height * olcek / 2,
                       width: o.width * olcek, height: o.height * olcek)
    resim.draw(in: hedef)
}

let govde = CGRect(x: 100, y: 100, width: 824, height: 824)
let sekil = CGPath(roundedRect: govde, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Gölge
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: renk(0, 0, 0, 0.35))
ctx.addPath(sekil)
ctx.setFillColor(renk(0, 0, 0))
ctx.fillPath()
ctx.restoreGState()

// Zemin: sakin yeşil degrade
ctx.saveGState()
ctx.addPath(sekil)
ctx.clip()
let zemin = CGGradient(colorsSpace: renkUzayi,
                       colors: [renk(0.16, 0.52, 0.43), renk(0.05, 0.25, 0.21)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(zemin, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
let isilti = CGGradient(colorsSpace: renkUzayi,
                        colors: [renk(1, 1, 1, 0.16), renk(1, 1, 1, 0)] as CFArray,
                        locations: [0, 1])!
ctx.drawRadialGradient(isilti, startCenter: CGPoint(x: 512, y: 700), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 700), endRadius: 520, options: [])
ctx.restoreGState()

// Yazıcı
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: renk(0, 0, 0, 0.25))
sembol("printer.fill", CGRect(x: 222, y: 250, width: 580, height: 500), NSColor(white: 0.98, alpha: 1))
ctx.restoreGState()

// Altın kilit rozeti
let rozet = CGRect(x: 612, y: 150, width: 260, height: 260)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: renk(0, 0, 0, 0.3))
let altin = CGGradient(colorsSpace: renkUzayi,
                       colors: [renk(0.99, 0.84, 0.42), renk(0.88, 0.63, 0.16)] as CFArray,
                       locations: [0, 1])!
ctx.addEllipse(in: rozet)
ctx.clip()
ctx.drawLinearGradient(altin, start: CGPoint(x: rozet.midX, y: rozet.maxY), end: CGPoint(x: rozet.midX, y: rozet.minY), options: [])
ctx.restoreGState()
ctx.addEllipse(in: rozet.insetBy(dx: 3, dy: 3))
ctx.setStrokeColor(renk(1, 1, 1, 0.85))
ctx.setLineWidth(8)
ctx.strokePath()
sembol("lock.fill", rozet.insetBy(dx: 70, dy: 62), NSColor(red: 0.20, green: 0.16, blue: 0.05, alpha: 1), agirlik: .semibold)

// İnce kenar
ctx.addPath(sekil)
ctx.setStrokeColor(renk(1, 1, 1, 0.10))
ctx.setLineWidth(4)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
