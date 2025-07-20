//
// BitchatApp.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import UserNotifications

struct BitchatApp: View {
    @State private var chatViewModel = BitchatViewModel()
    
    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }
    
    var body: some View {
        BitchatContentView()
            .environment(chatViewModel)
            .onAppear {
                chatViewModel.startServices()
                NotificationDelegate.shared.chatViewModel = chatViewModel
                // Check for shared content
                checkForSharedContent()
            }
//            .onOpenURL { url in
//                handleURL(url)
//            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Check for shared content when app becomes active
                checkForSharedContent()
            }
            #endif
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }
    
    private func handleURL(_ url: URL) {
        if url.scheme == "bitchat" && url.host == "share" {
            // Handle shared content
            checkForSharedContent()
        }
    }
    
    private func checkForSharedContent() {
        // Check app group for shared content from extension
        guard let userDefaults = UserDefaults(suiteName: "group.chat.bitchat") else {
            return
        }
        
        guard let sharedContent = userDefaults.string(forKey: "sharedContent"),
              let sharedDate = userDefaults.object(forKey: "sharedContentDate") as? Date else {
            return
        }
        
        // Only process if shared within last 30 seconds
        if Date().timeIntervalSince(sharedDate) < 30 {
            let contentType = userDefaults.string(forKey: "sharedContentType") ?? "text"
            
            // Clear the shared content
            userDefaults.removeObject(forKey: "sharedContent")
            userDefaults.removeObject(forKey: "sharedContentType")
            userDefaults.removeObject(forKey: "sharedContentDate")
            
            // Show notification about shared content
            DispatchQueue.main.async {
                // Add system message about sharing
                let systemMessage = BitchatMessage(
                    sender: "system",
                    content: "preparing to share \(contentType)...",
                    timestamp: Date(),
                    isRelay: false
                )
                self.chatViewModel.messages.append(systemMessage)
            }
            
            // Send the shared content after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if contentType == "url" {
                    // Try to parse as JSON first
                    if let data = sharedContent.data(using: .utf8),
                       let urlData = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                       let url = urlData["url"],
                       let title = urlData["title"] {
                        // Send just emoji with hidden markdown link
                        let markdownLink = "👇 [\(title)](\(url))"
                        self.chatViewModel.sendMessage(markdownLink)
                    } else {
                        // Fallback to simple URL
                        self.chatViewModel.sendMessage("Shared link: \(sharedContent)")
                    }
                } else {
                    self.chatViewModel.sendMessage(sharedContent)
                }
            }
        }
    }
}

@MainActor class NotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var chatViewModel: BitchatViewModel?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        
        // Check if this is a private message notification
        if identifier.hasPrefix("private-") {
            // Extract sender from notification title
            let title = response.notification.request.content.title
            if let senderName = title.replacingOccurrences(of: "Private message from ", with: "").nilIfEmpty {
                // Find peer ID and open chat
                if let peerID = chatViewModel?.getPeerIDForNickname(senderName) {
                    DispatchQueue.main.async {
                        self.chatViewModel?.startPrivateChat(with: peerID)
                    }
                }
            }
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground (for testing)
        completionHandler([.banner, .sound])
    }
}

extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
