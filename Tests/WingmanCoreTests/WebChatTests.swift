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
