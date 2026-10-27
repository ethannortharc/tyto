import Foundation
import NaturalLanguage
import SwiftUI

/// 字幕里的关键字高亮：数字/日期/金额、人名/地名/机构、会话里设的关键词。
/// 全在本机算（NaturalLanguage + NSDataDetector + 正则），不调模型。
@MainActor
enum Highlighter {
    enum Kind {
        case entity
        case number
        case keyword
    }

    private static var cache: [String: AttributedString] = [:]

    static func text(_ text: String, keywords: [String], theme: OverlayTheme, base: Color,
                     entities: Bool = true) -> AttributedString {
        // 白字、黑字的高亮颜色不同，底色也算进去
        let key = "\(theme.id.rawValue)|\(theme.light)|\(base)|\(entities)|\(keywords.joined(separator: ","))|\(text)"
        if let cached = cache[key] { return cached }
        let result = build(text, keywords: keywords, theme: theme, base: base, entities: entities)
        if cache.count > 600 { cache.removeAll() }
        cache[key] = result
        return result
    }

    private static func build(_ text: String, keywords: [String], theme: OverlayTheme, base: Color,
                              entities: Bool) -> AttributedString {
        var marks: [(NSRange, Kind)] = []
        let whole = NSRange(text.startIndex..., in: text)

        if entities {
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = text
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                                 options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
                if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                    marks.append((NSRange(range, in: text), .entity))
                }
                return true
            }
        }
        for match in detector?.matches(in: text, range: whole) ?? [] { marks.append((match.range, .number)) }
        for pattern in numberPatterns {
            for match in pattern.matches(in: text, range: whole) { marks.append((match.range, .number)) }
        }
        let nsText = text as NSString
        for keyword in keywords where keyword.count >= 2 {
            var searchRange = whole
            while searchRange.length > 0 {
                let found = nsText.range(of: keyword, options: [.caseInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }
                marks.append((found, .keyword))
                let next = found.location + found.length
                searchRange = NSRange(location: next, length: nsText.length - next)
            }
        }

        var result = AttributedString(text)
        result.foregroundColor = base
        // 后加的盖住先加的：关键词 > 数字 > 人名
        for kind in [Kind.entity, .number, .keyword] {
            for (range, markKind) in marks where markKind == kind {
                guard let stringRange = Range(range, in: text),
                      let lower = AttributedString.Index(stringRange.lowerBound, within: result),
                      let upper = AttributedString.Index(stringRange.upperBound, within: result)
                else { continue }
                let span = lower..<upper
                switch kind {
                case .entity:
                    result[span].foregroundColor = theme.entity
                case .number:
                    result[span].foregroundColor = theme.number
                    result[span].inlinePresentationIntent = .stronglyEmphasized
                case .keyword:
                    result[span].foregroundColor = theme.keyword
                    result[span].backgroundColor = theme.keyword.opacity(0.16)
                    result[span].inlinePresentationIntent = .stronglyEmphasized
                }
            }
        }
        return result
    }

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.link.rawValue)

    private static let numberPatterns: [NSRegularExpression] = [
        // 数字、金额、百分比、时间：$5,000、20%、3:30 pm、1.5M
        #"(?:[$€£¥]\s?)?\d[\d,.:]*(?:\s?(?:%|percent|k|K|M|B|million|billion|pm|am|PM|AM)\b)?"#,
        // 季度、英文月份和星期
        #"\b(?:Q[1-4]|H[12]|Jan(?:uary)?|Feb(?:ruary)?|March|Apr(?:il)?|June|July|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|tomorrow|tonight)\b"#,
        // 中文数字和日期：十二月、下周三、3 号、两万元
        #"(?:[上下本这]?(?:周|星期)[一二三四五六日天])|(?:[零一二三四五六七八九十百千两\d]+(?:月|号|日|点|周|天|个月|年|万|亿|元|块|美元|个人|次|%))"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }
}
