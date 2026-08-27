import Foundation

/// Отказ долговечной записи: на каком шаге и с каким `errno`.
///
/// Причина — значение, а не строка: вызывающий различает «не смог создать временный файл»
/// и «не смог синхронизировать каталог» сопоставлением case, а не разбором текста.
public enum DurableWriteError: Error, Equatable, Sendable {
    case cannotCreateTemporaryFile(errno: Int32)
    case writeFailed(errno: Int32)
    case fullSyncFailed(errno: Int32)
    case closeFailed(errno: Int32)
    case renameFailed(errno: Int32)
    case directorySyncFailed(errno: Int32)
}

/// Долговечно записывает байты по указанному пути.
///
/// Единственный способ, которым продукт пишет **любой** файл. Помимо конфига его зовут
/// TASK-007 (дневной rollup фокуса, DEC-005) и TASK-008 (plist автозапуска в
/// `~/Library/LaunchAgents`), поэтому хелпер знает только про переданный ему адрес: ни имя
/// `config.json`, ни каталог данных приложения, ни фиксированное имя временного файла
/// внутрь не зашиты. Имя временного файла выводится из имени назначения.
///
/// Шаги — ровно четыре, и порядок значим:
///
/// 1. временный файл рядом с назначением, `<имя-назначения>.sb-<uuid>`,
///    `O_WRONLY|O_CREAT|O_EXCL`, режим `0o644`;
/// 2. `fcntl(fd, F_FULLFSYNC)` на **том же** дескрипторе, которым писали, затем `close`;
/// 3. `rename(2)` на путь назначения — атомарная подмена;
/// 4. `open` каталога назначения на чтение и `fsync` его, чтобы запись самой директории
///    тоже дошла до устройства.
///
/// Штатный `Data.write` с флагом атомарности делает шаги 1 и 3, но **не делает** ни одного
/// `fsync` (findings §11): после сбоя питания на диске может не оказаться ни новой версии,
/// ни старой. Замер на 9 933 байтах: 0.26 мс против 6.73 мс здесь. При частоте записи
/// конфига разница не имеет значения, поэтому берётся долговечный вариант.
///
/// При успехе временного файла не остаётся. При ошибке хелпер убирает его сам, не
/// полагаясь на стартовую уборку: уборка ходит только по каталогу данных приложения, а
/// писать хелпер может куда угодно.
///
/// Каталог назначения должен существовать — хелпер его не создаёт.
public func writeDurably(_ bytes: Data, to destination: URL) throws {
    let directory = destination.deletingLastPathComponent()
    let temporary = directory.appendingPathComponent(
        destination.lastPathComponent + ".sb-" + UUID().uuidString,
        isDirectory: false
    )

    let descriptor = temporary.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else {
            errno = EINVAL
            return -1
        }
        return open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
    }
    guard descriptor >= 0 else {
        throw DurableWriteError.cannotCreateTemporaryFile(errno: errno)
    }

    do {
        try writeAll(bytes, to: descriptor)
        guard fcntl(descriptor, F_FULLFSYNC) != -1 else {
            throw DurableWriteError.fullSyncFailed(errno: errno)
        }
        guard close(descriptor) == 0 else {
            throw DurableWriteError.closeFailed(errno: errno)
        }
    } catch {
        // Дескриптор уже закрыт только на пути closeFailed; повторный close безвреден
        // и его код возврата ни на что не влияет — важно убрать хвост с диска.
        _ = close(descriptor)
        removeQuietly(temporary)
        throw error
    }

    let renamed = temporary.withUnsafeFileSystemRepresentation { source -> Int32 in
        guard let source else {
            errno = EINVAL
            return -1
        }
        return destination.withUnsafeFileSystemRepresentation { target -> Int32 in
            guard let target else {
                errno = EINVAL
                return -1
            }
            return rename(source, target)
        }
    }
    guard renamed == 0 else {
        let code = errno
        removeQuietly(temporary)
        throw DurableWriteError.renameFailed(errno: code)
    }

    let directoryDescriptor = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else {
            errno = EINVAL
            return -1
        }
        return open(path, O_RDONLY)
    }
    guard directoryDescriptor >= 0 else {
        throw DurableWriteError.directorySyncFailed(errno: errno)
    }
    let synced = fsync(directoryDescriptor)
    let syncErrno = errno
    _ = close(directoryDescriptor)
    guard synced == 0 else {
        throw DurableWriteError.directorySyncFailed(errno: syncErrno)
    }
}

/// Пишет все байты в дескриптор, доедая частичные записи и повторяя прерванные сигналом.
private func writeAll(_ bytes: Data, to descriptor: Int32) throws {
    try bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            guard let base = buffer.baseAddress else {
                throw DurableWriteError.writeFailed(errno: EINVAL)
            }
            let written = write(descriptor, base + offset, buffer.count - offset)
            if written <= 0 {
                if written < 0, errno == EINTR { continue }
                throw DurableWriteError.writeFailed(errno: written < 0 ? errno : EIO)
            }
            offset += written
        }
    }
}

/// Убирает хвост неудачной записи. Ошибка удаления здесь не диагностична: наружу идёт
/// причина самой неудачи, а не причина, по которой не удалось прибраться.
private func removeQuietly(_ url: URL) {
    _ = try? FileManager.default.removeItem(at: url)
}
