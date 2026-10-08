import Foundation

public struct ImageData: Sendable, Equatable {
    public var data: Data
    public var uti: String

    public init(data: Data, uti: String) {
        self.data = data
        self.uti = uti
    }
}

public struct CapturedContent: Sendable, Equatable {
    public var kind: ClipKind
    public var plainText: String
    public var rtf: Data?
    public var html: Data?
    public var image: ImageData?
    public var fileURLs: [URL]
    public var width: Int?
    public var height: Int?

    public init(
        kind: ClipKind,
        plainText: String,
        rtf: Data? = nil,
        html: Data? = nil,
        image: ImageData? = nil,
        fileURLs: [URL] = [],
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.kind = kind
        self.plainText = plainText
        self.rtf = rtf
        self.html = html
        self.image = image
        self.fileURLs = fileURLs
        self.width = width
        self.height = height
    }
}

public enum ClipPayload: Sendable, Equatable {
    case text(plain: String, rtf: Data?, html: Data?)
    case image(ImageData)
    case files([URL])
}

public enum IngestResult: Sendable, Equatable { case inserted(Int64), bumped(Int64) }

public enum HistoryLimit: Int, Sendable, CaseIterable {
    case l200 = 200, l1000 = 1000, l5000 = 5000, l10000 = 10000, unlimited = 0
}
