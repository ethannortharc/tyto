@preconcurrency import AVFAudio
import Foundation

/// 对比几家实时识别：同一段音频按真实速度同时送给每一家，比错字、说话人、延迟和价钱。
///   Tyto --compare-speech <音频> [--reference 参考稿.txt] [--providers soniox,assemblyai,elevenlabs]
///        [--hints en,zh] [--out 文件夹]
/// --providers 里可以写「服务商:模型」（如 assemblyai:universal-3-5-pro）；key 用「Tyto --set-key <服务商>」存的。
/// 也可以加上 Apple 本机识别当基准：apple:en-US、apple:zh-CN（一次只认一种语言）。
/// 参考稿是这段音频的正确文字；每行都写成「说话人: 文字」时，才算说话人分得对不对。
/// 结果写进 --out（默认当前文件夹下 compare-时间）：report.md（表格 + 每家的原文）、events.json（每条识别事件和到达时间）。
enum SpeechCompare {
    /// 参与对比的一家
    struct Contender: Sendable {
        let label: String
        /// nil = Apple 本机识别
        let kind: ProviderKind?
        let make: @Sendable () throws -> SpeechEngine
    }

    /// 一条识别事件和它到达的时间（秒，从开始送音频算）
    struct Timed: Sendable {
        let time: Double
        let event: SpeechEvent
    }

    /// 每家跑完的结果
    struct Result {
        let contender: Contender
        let timeline: [Timed]
        let startError: String?
    }

    /// 官网价（2026-10，美元/小时，开着识别就计费）：都算上区分说话人；ElevenLabs 实时版没有这项
    static let pricePerHour: [ProviderKind: Double] = [.soniox: 0.12, .assemblyai: 0.57, .elevenlabs: 0.39, .deepgram: 0.47]

    static let chunkSamples = 1_600

    static func run(file: String, reference: String?, providers list: String, hints: [String], out: String?,
                    settings: AppSettings) async -> Int32 {
        let contenders = contenders(list, hints: hints, settings: settings)
        guard !contenders.isEmpty else { return 1 }
        let samples: [Float]
        do {
            samples = try load(file)
        } catch {
            print("读不了音频：\(error.localizedDescription)")
            return 1
        }
        let referenceText = reference.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        if reference != nil, referenceText == nil { print("读不了参考稿：\(reference!)") }
        let duration = Double(samples.count) / Resampler.outputRate
        print("音频 \(clock(duration))，同时送给：\(contenders.map(\.label).joined(separator: "、"))")

        let results = await stream(samples, to: contenders)
        let report = Report(results: results, samples: samples, duration: duration,
                            reference: referenceText.map(ReferenceText.init), file: file)
        print("")
        print(report.table)
        let folder = URL(filePath: out ?? "compare-\(Self.stamp())")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try report.markdown.write(to: folder.appending(path: "report.md"), atomically: true, encoding: .utf8)
            try report.eventsJSON.write(to: folder.appending(path: "events.json"))
            print("\n报告：\(folder.appending(path: "report.md").path)")
        } catch {
            print("写不了报告：\(error.localizedDescription)")
            return 1
        }
        return results.contains { $0.startError == nil } ? 0 : 1
    }

    /// 「soniox,assemblyai:universal-3-5-pro」→ 每家用哪个服务商、哪个模型；没 key 的跳过
    static func contenders(_ list: String, hints: [String], settings: AppSettings) -> [Contender] {
        var result: [Contender] = []
        for item in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !item.isEmpty {
            let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
            let id = parts[0]
            if id == "apple" {
                let locale = parts.count > 1 ? parts[1] : "en-US"
                result.append(Contender(label: "Apple \(locale)", kind: nil, make: { AppleSpeechEngine(locale: locale) }))
                continue
            }
            let template = ProviderTemplate.find(id)
            guard let provider = settings.provider(id)
                    ?? template.map({ Provider(id: $0.id, name: $0.name, kind: $0.kind, baseURL: $0.baseURL, template: $0.id) }),
                  provider.kind.isStreamingSpeech else {
                print("「\(id)」不是实时识别服务，跳过（可选：soniox、assemblyai、elevenlabs、deepgram）")
                continue
            }
            guard provider.key != nil else {
                print("「\(id)」还没有 key，跳过（存 key：Tyto --set-key \(id) < key 文件）")
                continue
            }
            let model = parts.count > 1 ? parts[1]
                : settings.speechSlot.providerID == id ? settings.speechSlot.model
                : provider.info.suggested[.streamingSpeech]?.first ?? ""
            result.append(Contender(label: "\(provider.displayName) \(model)", kind: provider.kind, make: {
                try SpeechEngines.streaming(provider, model: model, languageHints: hints)
            }))
        }
        return result
    }

    /// 读音频，转成 16kHz 单声道
    static func load(_ file: String) throws -> [Float] {
        let audio = try AVAudioFile(forReading: URL(filePath: file))
        let format = audio.processingFormat
        guard let resampler = Resampler(inputRate: format.sampleRate),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else { throw TytoError.unsupportedAudioFormat }
        var samples: [Float] = []
        while audio.framePosition < audio.length {
            try audio.read(into: buffer, frameCount: 4_096)
            samples += resampler.process(Downmix.mono(buffer))
        }
        return samples
    }

    /// 每 100 ms 给每一家送一块，跟真的开会一样快；最后补 3 秒静音，让各家把最后一句定稿
    static func stream(_ samples: [Float], to contenders: [Contender]) async -> [Result] {
        let clock = ContinuousClock()
        // 先连上再开始计时，免得把握手的时间算进第一句的延迟
        let origin = clock.now + .milliseconds(1_500)
        var engines: [(Contender, SpeechEngine)] = []
        var results: [Int: Result] = [:]
        for (index, contender) in contenders.enumerated() {
            do {
                let engine = try contender.make()
                try await engine.start()
                engines.append((contender, engine))
            } catch {
                print("\(contender.label) 没启动：\(error.localizedDescription)")
                results[index] = Result(contender: contender, timeline: [], startError: error.localizedDescription)
            }
        }
        let collectors = engines.map { contender, engine in
            Task { () -> [Timed] in
                var timeline: [Timed] = []
                for await event in engine.events {
                    let time = (clock.now - origin).seconds
                    if event.kind == .error { print("  \(contender.label) 出错：\(event.text)") }
                    timeline.append(Timed(time: time, event: event))
                }
                return timeline
            }
        }

        let padded = samples + [Float](repeating: 0, count: Int(Resampler.outputRate) * 3)
        let chunks = (padded.count + chunkSamples - 1) / chunkSamples
        try? await clock.sleep(until: origin)
        for index in 0..<chunks {
            let chunk = Array(padded[index * chunkSamples..<min(padded.count, (index + 1) * chunkSamples)])
            for (_, engine) in engines { engine.append(chunk) }
            if index % 300 == 299 { print("已送 \(Self.clock(Double(index + 1) / 10)) / \(Self.clock(Double(samples.count) / Resampler.outputRate))") }
            try? await clock.sleep(until: origin + .milliseconds(100 * (index + 1)))
        }
        await withTaskGroup(of: Void.self) { group in
            for (_, engine) in engines { group.addTask { await engine.stop() } }
        }
        var started = zip(engines, collectors).makeIterator()
        var ordered: [Result] = []
        for index in contenders.indices {
            if let failed = results[index] {
                ordered.append(failed)
            } else if let ((contender, _), collector) = started.next() {
                ordered.append(Result(contender: contender, timeline: await collector.value, startError: nil))
            }
        }
        return ordered
    }

    static func clock(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

extension Duration {
    var seconds: Double {
        let (whole, fraction) = components
        return Double(whole) + Double(fraction) / 1e18
    }
}

// MARK: - 参考稿

/// 参考稿：每行一句；每行都是「说话人: 文字」时记下说话人
struct ReferenceText {
    let lines: [(speaker: String?, text: String)]

    init(_ text: String) {
        let raw = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let split = raw.map { line -> (String, String)? in
            guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }),
                  line.distance(from: line.startIndex, to: colon) <= 24 else { return nil }
            let speaker = line[..<colon].trimmingCharacters(in: .whitespaces)
            return speaker.isEmpty ? nil : (speaker, line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        lines = split.allSatisfy { $0 != nil }
            ? split.map { (speaker: Optional($0!.0), text: $0!.1) }
            : raw.map { (speaker: nil, text: $0) }
    }

    var hasSpeakers: Bool { lines.first?.speaker != nil }
}

// MARK: - 算分

/// 比较用的"字"：中日韩文字一个字算一个，其余按词；不分大小写、简繁，去掉标点
struct ScoreToken: Equatable {
    let text: String
    let cjk: Bool

    static func tokens(_ text: String) -> [ScoreToken] {
        let simplified = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
        let normalized = simplified.precomposedStringWithCompatibilityMapping.lowercased().replacingOccurrences(of: "’", with: "'")
        var result: [ScoreToken] = []
        var word = ""
        func flush() {
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            if !trimmed.isEmpty { result.append(ScoreToken(text: trimmed, cjk: false)) }
            word = ""
        }
        for scalar in normalized.unicodeScalars {
            if isCJKLetter(scalar) {
                flush()
                result.append(ScoreToken(text: String(scalar), cjk: true))
            } else if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                word.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    /// 汉字、假名、韩文（不含中文标点）
    static func isCJKLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isIdeographic || (0x3041...0x30FF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
    }
}

enum Alignment {
    /// 对齐的一步：参考稿第 i 个、识别结果第 j 个
    enum Step {
        case same(Int, Int)
        case substitute(Int, Int)
        /// 识别结果多出来的
        case insert(Int)
        /// 识别结果漏掉的
        case delete(Int)
    }

    /// 编辑距离；需要时一并给出每一步怎么对上的。太长（超过 1.5 亿格）就只算距离。
    static func align<T: Equatable>(_ reference: [T], _ hypothesis: [T], steps wantSteps: Bool) -> (distance: Int, steps: [Step]?) {
        let n = reference.count, m = hypothesis.count
        if n == 0 || m == 0 {
            return (max(n, m), wantSteps ? reference.indices.map(Step.delete) + hypothesis.indices.map(Step.insert) : nil)
        }
        let keepPath = wantSteps && n * m <= 150_000_000
        // 0 = 对上（相同或认错），1 = 识别结果多了一个，2 = 识别结果少了一个
        var path = keepPath ? [UInt8](repeating: 0, count: (n + 1) * (m + 1)) : []
        var previous = Array(0...m)
        var current = [Int](repeating: 0, count: m + 1)
        if keepPath { for j in 1...m { path[j] = 1 } }
        for i in 1...n {
            current[0] = i
            if keepPath { path[i * (m + 1)] = 2 }
            for j in 1...m {
                let match = previous[j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1)
                let insert = current[j - 1] + 1
                let delete = previous[j] + 1
                var best = match, step: UInt8 = 0
                if insert < best { best = insert; step = 1 }
                if delete < best { best = delete; step = 2 }
                current[j] = best
                if keepPath { path[i * (m + 1) + j] = step }
            }
            swap(&previous, &current)
        }
        guard keepPath else { return (previous[m], nil) }
        var steps: [Step] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            switch path[i * (m + 1) + j] {
            case 0 where i > 0 && j > 0:
                steps.append(reference[i - 1] == hypothesis[j - 1] ? .same(i - 1, j - 1) : .substitute(i - 1, j - 1))
                i -= 1
                j -= 1
            case 1 where j > 0:
                steps.append(.insert(j - 1))
                j -= 1
            default:
                steps.append(.delete(i - 1))
                i -= 1
            }
        }
        return (previous[m], steps.reversed())
    }

    /// 每个错算到参考稿的哪个位置上：认错、漏掉的就是那个字；多出来的算到前一个字（开头的算到第一个字）
    static func errorPositions(_ steps: [Step]) -> [Int] {
        var positions: [Int] = []
        var last: Int?
        var leading = 0
        for step in steps {
            switch step {
            case .same(let i, _):
                last = i
            case .substitute(let i, _), .delete(let i):
                positions.append(i)
                last = i
            case .insert:
                if let last { positions.append(last) } else { leading += 1 }
            }
        }
        if leading > 0, let first = steps.lazy.compactMap({ step -> Int? in
            switch step {
            case .same(let i, _), .substitute(let i, _), .delete(let i): i
            case .insert: nil
            }
        }).first {
            positions += Array(repeating: first, count: leading)
        }
        return positions
    }
}

/// 音频里哪几段有人说话（按音量算，够用来量延迟）
enum SpeechActivity {
    static func segments(_ samples: [Float], rate: Double = Resampler.outputRate) -> [(start: Double, end: Double)] {
        let frame = Int(rate * 0.02)
        guard samples.count >= frame else { return [] }
        let levels = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start -> Float in
            var sum: Float = 0
            for index in start..<start + frame { sum += samples[index] * samples[index] }
            return (sum / Float(frame)).squareRoot()
        }
        let floor = levels.sorted()[levels.count / 10]
        let threshold = max(0.003, floor * 3)
        var segments: [(start: Double, end: Double)] = []
        for (index, level) in levels.enumerated() where level > threshold {
            let time = Double(index) * 0.02
            // 中间停不到 0.4 秒算同一段
            if let last = segments.indices.last, time - segments[last].end < 0.4 {
                segments[last].end = time + 0.02
            } else {
                segments.append((time, time + 0.02))
            }
        }
        return segments.filter { $0.end - $0.start >= 0.15 }
    }
}

// MARK: - 报告

struct Report {
    struct Line {
        var speaker: Int?
        var text: String
        var time: Double
    }

    struct Scores {
        var lines: [Line] = []
        var errors = 0
        var allErrorRate: Double?
        var chineseErrorRate: Double?
        var englishErrorRate: Double?
        var speakerAccuracy: Double?
        var speakers = 0
        var firstText: [Double] = []
        var finalLag: [Double] = []
        var missedEnds = 0
        var pauses = 0
        var firstError: String?
    }

    let results: [SpeechCompare.Result]
    let samples: [Float]
    let duration: Double
    let reference: ReferenceText?
    let file: String
    let scores: [Scores]

    init(results: [SpeechCompare.Result], samples: [Float], duration: Double, reference: ReferenceText?, file: String) {
        self.results = results
        self.samples = samples
        self.duration = duration
        self.reference = reference
        self.file = file
        let segments = SpeechActivity.segments(samples)
        scores = results.map { Self.score($0, segments: segments, reference: reference) }
    }

    /// 把一家的识别事件整理成一行行（换人或一句说完就换行），再算分
    static func score(_ result: SpeechCompare.Result, segments: [(start: Double, end: Double)], reference: ReferenceText?) -> Scores {
        var scores = Scores()
        var open = false
        let reportsEnds = result.timeline.contains { $0.event.kind == .endOfUtterance }
        for timed in result.timeline {
            let event = timed.event
            switch event.kind {
            case .final:
                let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).isEmpty else { continue }
                if open, let last = scores.lines.indices.last, scores.lines[last].speaker == event.speaker || event.speaker == nil {
                    scores.lines[last].text = TextJoin.join(scores.lines[last].text, text)
                } else {
                    scores.lines.append(Line(speaker: event.speaker, text: text, time: timed.time))
                    open = true
                }
                if !reportsEnds { open = false }
            case .endOfUtterance:
                open = false
            case .error:
                scores.errors += 1
                if scores.firstError == nil { scores.firstError = event.text }
            case .partial:
                break
            }
        }
        scores.speakers = Set(scores.lines.compactMap(\.speaker)).count

        if let reference {
            let refTokens = reference.lines.flatMap { line in ScoreToken.tokens(line.text).map { ($0, line.speaker) } }
            let hypTokens = scores.lines.flatMap { line in ScoreToken.tokens(line.text).map { ($0, line.speaker) } }
            let full = Alignment.align(refTokens.map(\.0), hypTokens.map(\.0), steps: true)
            scores.allErrorRate = refTokens.isEmpty ? nil : Double(full.distance) / Double(refTokens.count)
            // 中文、英文各自的错误率：错误按它在参考稿里的位置归到那种语言（中文段里冒出来的英文乱码算中文的错）
            func rate(cjk: Bool) -> Double? {
                let count = refTokens.filter { $0.0.cjk == cjk }.count
                guard count > 0 else { return nil }
                if let steps = full.steps {
                    return Double(Alignment.errorPositions(steps).filter { refTokens[$0].0.cjk == cjk }.count) / Double(count)
                }
                // 太长没留对齐路径：只拿这种语言的字各自比
                let ref = refTokens.map(\.0).filter { $0.cjk == cjk }, hyp = hypTokens.map(\.0).filter { $0.cjk == cjk }
                return Double(Alignment.align(ref, hyp, steps: false).distance) / Double(count)
            }
            scores.chineseErrorRate = rate(cjk: true)
            scores.englishErrorRate = rate(cjk: false)
            if reference.hasSpeakers, scores.speakers > 0, let steps = full.steps {
                let pairs = steps.compactMap { step -> (String, Int?)? in
                    switch step {
                    case .same(let i, let j), .substitute(let i, let j): (refTokens[i].1 ?? "", hypTokens[j].1)
                    case .insert, .delete: nil
                    }
                }
                if !pairs.isEmpty { scores.speakerAccuracy = speakerAccuracy(pairs) }
            }
        }

        // 首字：前面安静了 1.5 秒以上的一段话，开口后多久出第一个字
        let texts = result.timeline.filter { ($0.event.kind == .partial || $0.event.kind == .final) && !$0.event.text.isEmpty }
        for (index, segment) in segments.enumerated() where index == 0 || segment.start - segments[index - 1].end >= 1.5 {
            if let first = texts.first(where: { $0.time >= segment.start }), first.time - segment.start < 5 {
                scores.firstText.append(first.time - segment.start)
            }
        }
        // 定稿：停顿 0.6 秒以上（一句说完）后，多久收到"这句说完了"；不报一句说完的（Apple）看定稿的字
        let endKind: SpeechEvent.Kind = reportsEnds ? .endOfUtterance : .final
        let ends = result.timeline.filter { $0.event.kind == endKind }.map(\.time)
        for (index, segment) in segments.enumerated() {
            let next = index + 1 < segments.count ? segments[index + 1] : nil
            guard next.map({ $0.start - segment.end >= 0.6 }) ?? true else { continue }
            scores.pauses += 1
            let limit = min(segment.end + 5, next?.end ?? .infinity)
            if let end = ends.first(where: { $0 >= segment.end && $0 < limit }) {
                scores.finalLag.append(end - segment.end)
            } else {
                scores.missedEnds += 1
            }
        }
        return scores
    }

    /// 说话人分对的比例：识别结果里的每个人对应到参考稿里说得最多的那个人（一对一），再数对上的字
    static func speakerAccuracy(_ pairs: [(reference: String, hypothesis: Int?)]) -> Double {
        var counts: [Int: [String: Int]] = [:]
        for pair in pairs {
            guard let hypothesis = pair.hypothesis else { continue }
            counts[hypothesis, default: [:]][pair.reference, default: 0] += 1
        }
        let candidates = counts.flatMap { hypothesis, references in references.map { (hypothesis, $0.key, $0.value) } }
            .sorted { $0.2 > $1.2 }
        var mapping: [Int: String] = [:]
        var used: Set<String> = []
        for (hypothesis, reference, _) in candidates where mapping[hypothesis] == nil && !used.contains(reference) {
            mapping[hypothesis] = reference
            used.insert(reference)
        }
        let correct = pairs.filter { pair in pair.hypothesis.flatMap { mapping[$0] } == pair.reference }.count
        return Double(correct) / Double(pairs.count)
    }

    private static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func p90(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
    }

    private static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.2f s", $0) } ?? "—"
    }

    var table: String {
        var rows = ["| 服务 | 总错误率 | 中文字 | 英文词 | 说话人分对 | 认出几人 | 首字（中位） | 说完到定稿（中位 / 90%） | 没定稿的停顿 | 每小时 | 出错 |",
                    "|---|---|---|---|---|---|---|---|---|---|---|"]
        for (result, score) in zip(results, scores) {
            let price = result.contender.kind.map { kind in SpeechCompare.pricePerHour[kind].map { String(format: "$%.2f", $0) } ?? "—" } ?? "免费"
            let speakers = score.speakers == 0 ? "不分" : "\(score.speakers)"
            let accuracy = score.speakers == 0 ? "不分" : Self.percent(score.speakerAccuracy)
            let errors = result.startError != nil ? "没启动" : score.errors == 0 ? "0" : "\(score.errors)"
            rows.append("| \(result.contender.label) | \(Self.percent(score.allErrorRate)) | \(Self.percent(score.chineseErrorRate)) | \(Self.percent(score.englishErrorRate)) | \(accuracy) | \(speakers) | \(Self.seconds(Self.median(score.firstText))) | \(Self.seconds(Self.median(score.finalLag))) / \(Self.seconds(Self.p90(score.finalLag))) | \(score.missedEnds) / \(score.pauses) | \(price) | \(errors) |")
        }
        return rows.joined(separator: "\n")
    }

    var markdown: String {
        var text = """
        # 实时识别对比

        - 音频：`\(file)`，\(SpeechCompare.clock(duration))，按真实速度同时送给每一家
        - 参考稿：\(reference.map { "\($0.lines.count) 句" + ($0.hasSpeakers ? "，标了说话人" : "，没标说话人") } ?? "没有（只比延迟和说话人数）")

        \(table)

        - 错误率 = 编辑距离 ÷ 参考稿的字数；中文一个字算一个，英文一个词算一个；不分大小写、简繁，不算标点。数字写法不同（「三十」和「30」）也算错。
        - 说话人分对：识别结果里的每个人一对一对应到参考稿里的人，再数对上的字里说话人也对的比例。
        - 首字：前面安静 1.5 秒以上的一段话，开口到出第一个字；说完到定稿：停顿 0.6 秒以上时，到收到"这句说完了"。都按音量判断哪里有人说话，是估计值。
        - 每小时：2026-10 官网价，含区分说话人；Tyto 两路都开就是两倍。

        """
        if let reference {
            text += "\n## 参考稿\n\n"
            text += reference.lines.map { line in (line.speaker.map { "**\($0)**：" } ?? "") + line.text }.joined(separator: "\n\n")
            text += "\n"
        }
        for (result, score) in zip(results, scores) {
            text += "\n## \(result.contender.label)\n\n"
            if let error = result.startError ?? score.firstError { text += "> 出错：\(error)\n\n" }
            text += score.lines.map { line in
                "`\(SpeechCompare.clock(line.time))` " + (line.speaker.map { "**说话人\($0 + 1)**：" } ?? "") + line.text
            }.joined(separator: "\n\n")
            text += "\n"
        }
        return text
    }

    var eventsJSON: Data {
        let payload = results.map { result -> [String: Any] in
            [
                "label": result.contender.label,
                "events": result.timeline.map { timed -> [String: Any] in
                    var event: [String: Any] = ["t": (timed.time * 1000).rounded() / 1000, "kind": "\(timed.event.kind)", "text": timed.event.text]
                    if let speaker = timed.event.speaker { event["speaker"] = speaker }
                    if let language = timed.event.language { event["language"] = language }
                    return event
                },
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
