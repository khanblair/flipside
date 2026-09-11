public struct Note: Equatable, Sendable {
    public var id: String
    public var identityKey: String
    public var identityTier: IdentityTier
    public var body: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var bundleID: String
    public var appName: String
    public var lastTitle: String?
    public var lastDocPath: String?

    public init(
        id: String,
        identityKey: String,
        identityTier: IdentityTier,
        body: String,
        createdAt: Int64,
        updatedAt: Int64,
        bundleID: String,
        appName: String,
        lastTitle: String?,
        lastDocPath: String?
    ) {
        self.id = id
        self.identityKey = identityKey
        self.identityTier = identityTier
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bundleID = bundleID
        self.appName = appName
        self.lastTitle = lastTitle
        self.lastDocPath = lastDocPath
    }
}
