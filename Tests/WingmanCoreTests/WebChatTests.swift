import Foundation
import Testing
@testable import WingmanCore

@Test func knowsEachWebChatByItsAddress() {
    #expect(WebChat.at(URL(string: "https://www.messenger.com/t/123")!) == .messenger)
    #expect(WebChat.at(URL(string: "https://www.facebook.com/messages/t/123")!) == .messenger)
    #expect(WebChat.at(URL(string: "https://www.instagram.com/direct/t/123/")!) == .instagram)
    #expect(WebChat.at(URL(string: "https://www.threads.com/messages/t/123")!) == .threads)
    #expect(WebChat.at(URL(string: "https://www.threads.net/messages/t/123")!) == .threads)
}

@Test func readsOnlyTheChatPagesOfThoseSites() {
    // The feed, profiles and posts are not chats, and nothing on them is read.
    #expect(WebChat.at(URL(string: "https://www.facebook.com/")!) == nil)
    #expect(WebChat.at(URL(string: "https://www.instagram.com/")!) == nil)
    #expect(WebChat.at(URL(string: "https://www.instagram.com/someone/")!) == nil)
    #expect(WebChat.at(URL(string: "https://www.threads.com/@someone/post/abc")!) == nil)
}

@Test func lookalikeHostsAreNotTheRealSites() {
    #expect(WebChat.at(URL(string: "https://evilmessenger.com/t/1")!) == nil)
    #expect(WebChat.at(URL(string: "https://instagram.com.example.net/direct/t/1")!) == nil)
    #expect(WebChat.at(URL(string: "https://notthreads.com/messages/t/1")!) == nil)
    #expect(WebChat.at(URL(string: "https://example.com/www.instagram.com/direct/t/1")!) == nil)
    #expect(WebChat.at(URL(string: "http://www.instagram.com/direct/t/1")!) == nil)
}

@Test func aTabTitleOnlyHintsThatTheAddressIsWorthReading() {
    #expect(WebChat.mayBe(title: "Instagram • 訊息 - Google Chrome"))
    #expect(WebChat.mayBe(title: "(2) Threads"))
    #expect(WebChat.mayBe(title: "Messenger"))
    #expect(!WebChat.mayBe(title: "GitHub - Google Chrome"))
}

@Test func postsAreConsideredOnInstagramAndThreadsOnly() {
    // Anywhere on these two sites a reply box can open; the reader still needs one to have focus.
    #expect(WebChat.posts(URL(string: "https://www.instagram.com/")!) == .instagram)
    #expect(WebChat.posts(URL(string: "https://www.instagram.com/p/abc/")!) == .instagram)
    #expect(WebChat.posts(URL(string: "https://www.threads.com/@someone/post/abc")!) == .threads)
    #expect(WebChat.posts(URL(string: "https://www.threads.net/")!) == .threads)
    // Messages pages are read as chats, and Facebook's feed is not in scope.
    #expect(WebChat.posts(URL(string: "https://www.instagram.com/direct/t/1/")!) == nil)
    #expect(WebChat.posts(URL(string: "https://www.threads.com/messages/t/1")!) == nil)
    #expect(WebChat.posts(URL(string: "https://www.facebook.com/")!) == nil)
    #expect(WebChat.posts(URL(string: "https://instagram.com.example.net/p/abc/")!) == nil)
    #expect(WebChat.posts(URL(string: "http://www.instagram.com/p/abc/")!) == nil)
}
