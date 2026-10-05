import Foundation

// Pomocniki feedu — URL-e obrazów i polski czas względny, mirror webu.

enum FeedImageURL {
    /// Mirror getImageUrl z webu (src/images/client.ts): Cloudflare Images
    /// delivery; placeholdery testowe ("placeholder-…") → picsum, ten sam format.
    static func url(cfImageId: String, accountHash: String, variant: String = "thumbnail") -> URL? {
        if cfImageId.hasPrefix("placeholder-") {
            let seed = cfImageId.dropFirst("placeholder-".count)
            let size = variant == "thumbnail" ? "400/400" : "1200/800"
            return URL(string: "https://picsum.photos/seed/\(seed)/\(size)")
        }
        return URL(string: "https://imagedelivery.net/\(accountHash)/\(cfImageId)/\(variant)")
    }
}

enum RelativeTime {
    /// Czas względny po polsku — 1:1 z webem (post-card.tsx formatRelativeTime):
    /// „przed chwilą", „N min temu", „N godz. temu", „N dn. temu", dalej data pl-PL.
    static func polish(_ date: Date, now: Date = Date()) -> String {
        let diffMinutes = Int(now.timeIntervalSince(date) / 60)
        if diffMinutes < 1 { return "przed chwilą" }
        if diffMinutes < 60 { return "\(diffMinutes) min temu" }
        let diffHours = diffMinutes / 60
        if diffHours < 24 { return "\(diffHours) godz. temu" }
        let diffDays = diffHours / 24
        if diffDays < 7 { return "\(diffDays) dn. temu" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
