import CoreGraphics
import Foundation
import ImageIO

/// Synthetic solid-colour images only.
enum TestImages {
    static func png(width: Int, height: Int) -> Data {
        encode(width: width, height: height, type: "public.png")
    }

    static func tiff(width: Int, height: Int) -> Data {
        encode(width: width, height: height, type: "public.tiff")
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }

    private static func encode(width: Int, height: Int, type: String) -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fatalError("could not create CGContext") }
        context.setFillColor(CGColor(srgbRed: 1, green: 0.533, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { fatalError("could not make CGImage") }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type as CFString, 1, nil) else {
            fatalError("could not create CGImageDestination")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("could not encode image") }
        return out as Data
    }
}
