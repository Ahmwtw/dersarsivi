import Foundation

/// Kalıcı iş kuyruğundaki tek iş: bir sayfanın metninin çıkarılması.
public struct ExtractionJob: Codable, Equatable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable {
        case queued
        case processing
        case done
        case failed
        case cancelled
    }

    public var id: UUID
    public var pageID: UUID
    public var state: State
    public var attempts: Int
    public var lastError: String?
    public var updatedAt: Date
    /// Kullanıcı açıkça yeniden okumak istedi: aynı ayarla yapılmış eski çıkarım kullanılmaz.
    public var force: Bool?

    public init(id: UUID = UUID(), pageID: UUID, updatedAt: Date) {
        self.id = id
        self.pageID = pageID
        self.state = .queued
        self.attempts = 0
        self.lastError = nil
        self.updatedAt = updatedAt
    }
}

/// Uygulama kapanıp açılınca kaldığı yerden devam eden basit kuyruk.
/// iOS arka planda çalışmayı garanti etmediği için ön plana dönüşte `recoverInterrupted` çağrılır.
public struct JobQueue: Codable, Equatable, Sendable {
    public private(set) var jobs: [ExtractionJob] = []
    public var maxAttempts: Int

    public init(maxAttempts: Int = 3) {
        self.maxAttempts = maxAttempts
    }

    /// Aynı sayfa için bekleyen veya çalışan iş varsa yenisini eklemez (idempotent).
    @discardableResult
    public mutating func enqueue(pageID: UUID, at date: Date, force: Bool = false) -> ExtractionJob {
        if let i = jobs.firstIndex(where: { $0.pageID == pageID && ($0.state == .queued || $0.state == .processing) }) {
            if force { jobs[i].force = true }
            return jobs[i]
        }
        var job = ExtractionJob(pageID: pageID, updatedAt: date)
        if force { job.force = true }
        jobs.append(job)
        return job
    }

    /// Silinen sayfaların işlerini kaldırır.
    public mutating func remove(pageIDs: Set<UUID>) {
        jobs.removeAll { pageIDs.contains($0.pageID) }
    }

    /// Sıradaki işi alır ve `processing` yapar.
    public mutating func claimNext(at date: Date) -> ExtractionJob? {
        guard let i = jobs.firstIndex(where: { $0.state == .queued }) else { return nil }
        jobs[i].state = .processing
        jobs[i].attempts += 1
        jobs[i].updatedAt = date
        return jobs[i]
    }

    public mutating func complete(jobID: UUID, at date: Date) {
        update(jobID) { $0.state = .done; $0.lastError = nil; $0.updatedAt = date }
    }

    /// Hata: deneme hakkı kaldıysa tekrar sıraya, yoksa `failed`.
    public mutating func fail(jobID: UUID, error: String, at date: Date) {
        let max = maxAttempts
        update(jobID) {
            $0.lastError = error
            $0.state = $0.attempts < max ? .queued : .failed
            $0.updatedAt = date
        }
    }

    public mutating func cancel(jobID: UUID, at date: Date) {
        update(jobID) {
            if $0.state == .queued || $0.state == .processing { $0.state = .cancelled }
            $0.updatedAt = date
        }
    }

    /// Uygulama `processing` durumunda kapandıysa bu işler yeniden sıraya alınır.
    public mutating func recoverInterrupted(at date: Date) {
        for i in jobs.indices where jobs[i].state == .processing {
            jobs[i].state = .queued
            jobs[i].updatedAt = date
        }
    }

    public var pending: [ExtractionJob] { jobs.filter { $0.state == .queued || $0.state == .processing } }

    private mutating func update(_ id: UUID, _ change: (inout ExtractionJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }
}
