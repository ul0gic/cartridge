import AppKit

// Merged circles at the left become smaller print dots toward the right.
// The lower edge widens into the foot of the L. Console changes only recolor it.
let width = 3072
let height = 2048
let pitch = 14.0
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Cannot create the mask context") }
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: Double(width) * 0.22, height: Double(height)))
for row in 0...Int(Double(height) / pitch) {
    let y = Double(row) * pitch
    let bottom = pow(max(0, 1 - y / (Double(height) * 0.16)), 2)
    for column in 0...Int(Double(width) / pitch) {
        let x = Double(column) * pitch
        let progress = min(1, max(0, (x / Double(width) - 0.22 - bottom * 0.18) / 0.58))
        let coverage = 1 - progress * progress * (3 - 2 * progress)
        let radius = pitch * 0.76 * pow(coverage, 1.5)
        if radius > 0.18 {
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
    }
}

guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fatalError("Cannot encode the mask") }
let output = URL(fileURLWithPath: "Cartridge/App/Resources/Assets.xcassets/ConsoleFrameMask.imageset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try png.write(to: output.appendingPathComponent("console-frame-mask.png"))
