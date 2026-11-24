import Foundation
import UIKit

/// Сторож главного потока: ловит зависание интерфейса.
/// - Короткое зависание (больше 3 секунд, потом отпустило): сбрасываем весь интерфейс
///   и возвращаем на главный экран, показывая «Загрузка…».
/// - Долгое (больше 15 секунд, интерфейс мёртв): запоминаем это и закрываем приложение,
///   чтобы не висеть. Следующий запуск начнётся с чистого главного экрана и скажет об этом.
/// Если телефон подключён к Xcode (отладчик), приложение не закрывается.
final class Watchdog: @unchecked Sendable {
    static let shared = Watchdog()
    static let killedKey = "watchdog.killedAt"

    private let lock = NSLock()
    private var lastBeat = Date.now.timeIntervalSince1970
    private var active = false
    private var started = false
    private var watcher: DispatchSourceTimer?

    private let softStall: TimeInterval = 3
    private let hardStall: TimeInterval = 15

    /// Вызывается на главном потоке, когда зависание закончилось.
    @MainActor var onRecovered: (() -> Void)?

    /// Запустить сторожа (один раз). Вызывать на главном потоке.
    @MainActor
    func start() {
        guard !started else { return }
        started = true
        beat()

        // Сердцебиение на главном потоке.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.mainBeat()
        }
        RunLoop.main.add(timer, forMode: .common)

        // Наблюдатель на фоновом потоке.
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "watchdog", qos: .utility))
        source.schedule(deadline: .now() + 2, repeating: 1)
        source.setEventHandler { [weak self] in self?.check() }
        source.resume()
        watcher = source
    }

    /// Приложение на экране или нет (в фоне главный поток спит, это не зависание).
    func setActive(_ value: Bool) {
        lock.lock()
        active = value
        lastBeat = Date.now.timeIntervalSince1970
        lock.unlock()
    }

    private func beat() {
        lock.lock()
        lastBeat = Date.now.timeIntervalSince1970
        lock.unlock()
    }

    private func mainBeat() {
        let now = Date.now.timeIntervalSince1970
        lock.lock()
        let gap = now - lastBeat
        let isActive = active
        lastBeat = now
        lock.unlock()
        if isActive && gap > softStall {
            Task { @MainActor in self.onRecovered?() }
        }
    }

    private func check() {
        lock.lock()
        let gap = Date.now.timeIntervalSince1970 - lastBeat
        let isActive = active
        lock.unlock()
        guard isActive, gap > hardStall, !Self.debuggerAttached else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.killedKey)
        UserDefaults.standard.synchronize()
        exit(0)
    }

    private static var debuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
