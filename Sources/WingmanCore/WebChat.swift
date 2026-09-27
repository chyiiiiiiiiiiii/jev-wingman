import Foundation

/// A chat that lives in a browser tab. Instagram's and Threads' messages are Messenger underneath,
/// so all three share one layout and one parser.
public enum WebChat: String, CaseIterable {
    case messenger, instagram, threads

    /// Which web chat a page is: by exact host (evilmessenger.com is not Messenger), and only its chat
    /// pages, so a feed, profile or post is never read.
    public static func at(_ url: URL) -> WebChat? {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        func within(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        let path = url.path
        if within("messenger.com") || (within("facebook.com") && path.hasPrefix("/messages")) { return .messenger }
        if within("instagram.com") && path.hasPrefix("/direct/") { return .instagram }
        if (within("threads.com") || within("threads.net")) && path.hasPrefix("/messages") { return .threads }
        return nil
    }

    /// Instagram or Threads outside their messages, where a reply box can open under any post: in the feed,
    /// on a post's page, in a reply dialog. Only a reply box that has focus, and the post it answers, is read.
    public static func posts(_ url: URL) -> WebChat? {
        guard url.scheme == "https", let host = url.host?.lowercased(), at(url) == nil else { return nil }
        func within(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if within("instagram.com") { return .instagram }
        if within("threads.com") || within("threads.net") { return .threads }
        return nil
    }

    /// A browser shows a page's address only once its accessibility tree is built. A tab title naming one
    /// of these sites is reason to build it; the address still decides whether anything is read.
    public static func mayBe(title: String) -> Bool {
        ["messenger", "instagram", "threads"].contains { title.localizedCaseInsensitiveContains($0) }
    }
}
