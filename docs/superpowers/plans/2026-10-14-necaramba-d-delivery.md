# Necaramba D — Model Delivery, Licensing and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Доставлять независимо созданные проверенные правила, явно выбранные пользовательские сообщения и собственные entitlement, затем выпускать проверенный universal macOS app.

**Architecture:** RuleUpdates проверяет пакет вне input executor, атомарно публикует immutable snapshot через контракт B. Сеть, sharing и лицензирование изолированы адаптерами; offline ввод не зависит от их доступности. Developer ID — основной канал, StoreKit и MAS имеют отдельные gates.

**Tech Stack:** Swift tools 5.9; Swift 6 compiler в language mode 5; AppKit, Foundation URLSession, CryptoKit Curve25519.Signing, StoreKit 2, XCTest, Flutter Runner, Xcode scheme `Runner`.

**Spec:** `docs/superpowers/specs/2026-10-14-necaramba-design.md`, разделы 8, 10–12.

## Global Constraints

- Flutter/Dart для UI, Swift/AppKit для нативного ядра; минимальная macOS 12.0; архитектуры arm64 и x86_64.
- Основной цикл ввода работает локально и без сети.
- Callback event tap не выполняет сеть, файловый ввод-вывод или блокирующие AX-вызовы.
- Не сохранять и не отправлять набранный текст по умолчанию.
- При неопределённом фокусе, Secure Input, IME/composition или недоступных разрешениях пропускать ввод без изменения.
- Синтетические события маркируются и не обрабатываются повторно.
- Код, идентификаторы сервисов, модели, звуки, графика и аккаунты сторонних переключателей не входят в распространяемый продукт.
- Не выпускать функцию как совместимую без соответствующего теста и результата в матрице приёмки.

---

Статус: **план для ревью, код не реализован, команды и commits ниже не выполнялись**. Все пути proposed. Выполнять после A (типы/базовый corpus); интеграция требует B (граница edit transaction) и C (UI/preferences). Другие исполнители работают параллельно: не менять их файлы и не откатывать чужие изменения. Изменения `Package.swift`/Xcode project согласовывает интегратор.

## Владение файлами и контракты

D владеет `Sources/NecarambaCore/Delivery/`, `Sources/NecarambaCore/Licensing/`, `Sources/NecarambaMac/Delivery/`, `Sources/NecarambaMac/Licensing/`, `Tests/NecarambaCoreTests/Delivery/`, `Tests/NecarambaCoreTests/Licensing/`, `Tests/NecarambaMacTests/Delivery/`, `Tests/NecarambaMacTests/Licensing/`, `App/macos/Runner/Release/`, `Tools/Release/`, `docs/release/`. CoreTypes из A не дублировать. Test files импортируют XCTest, Foundation и `@testable import NecarambaCore`; Mac tests дополнительно `@testable import NecarambaMac`; cryptographic fixtures импортируют CryptoKit.

A предоставляет Codable/Equatable/Sendable `RuleSnapshot` с `modelVersion: UInt64`, `lexicon: [Lexeme]`, `typos: [ReplacementRule]`, `yoRules: [ReplacementRule]`, `protectedTokens: Set<String>`, `mappings: [LayoutMapping]`; `Lexeme(word: String, language: Language, frequencyBand: UInt8)`; `Language.english/.russian`; `ReplacementRule(source: String, target: String, caseSensitive: Bool)`; `LayoutMapping(source: LayoutID, target: LayoutID, pairs: [String:String])`; `LayoutID(rawValue: String)`, RawRepresentable/Codable/Hashable/Sendable. Явные init у всех; empty collections допустимы в unit fixtures, production validator требует содержимое.

D определяет в `Sources/NecarambaCore/Delivery/RuleSnapshotConsumer.swift`:

```swift
public protocol RuleSnapshotConsumer: AnyObject {
    func install(_ snapshot: RuleSnapshot)
}
```

Реализация B ставит snapshot на свой serial executor, откладывает swap до окончания текущей edit transaction; один decision всегда использует одну версию. `install` означает enqueue, не завершение swap; published UI version приходит из B после фактической установки. У updater только один serial producer; повторная доставка идентичной версии идемпотентна. `VerifiedRuleSnapshot` содержит те же rule data через `snapshot: RuleSnapshot`, computed `modelVersion: UInt64`, а также digest; конструктор закрыт за verifier.

### Task 1: Подпись, формат и проверенный snapshot

**Files:**
- Create: `Sources/NecarambaCore/Delivery/RuleManifest.swift`, `RulePackageVerifier.swift`, `RuleSnapshotConsumer.swift`; `VerifiedRuleSnapshot` объявить в `RulePackageVerifier.swift` для закрытого construction boundary.
- Test: `Tests/NecarambaCoreTests/Delivery/RulePackageVerifierTests.swift`.
- Create: `Tools/Release/SignRulePackage.swift`, `docs/release/rule-format-v1.md`.

**Interfaces:** Consumes типы A выше. Produces:

```swift
public struct RuleManifest: Codable, Equatable, Sendable {
    public let schemaVersion: UInt32
    public let modelVersion: UInt64
    public let minimumAppVersion: String
    public let payloadSize: UInt64
    public let payloadSHA256: String
    public let keyID: String
}
public struct VerifiedRuleSnapshot: Sendable {
    public let snapshot: RuleSnapshot
    public let digest: String
    public var modelVersion: UInt64 { snapshot.modelVersion }
    fileprivate init(snapshot: RuleSnapshot, digest: String) {
        self.snapshot = snapshot; self.digest = digest
    }
}
public enum RuleVerificationError: Error, Equatable {
    case invalidSignature, unknownKey, hashMismatch, sizeMismatch
    case incompatibleSchema, incompatibleApp, downgrade, invalidPayload
}
```

Конструктор и verifier разместить в одном `RulePackageVerifier.swift`; не делать init public/internal ради обхода проверок. Verifier init: `init(trustedKeys: [String: Data], appVersion: String)`; method `verify(manifest: Data, signature: Data, payload: Data, installedVersion: UInt64) throws -> VerifiedRuleSnapshot`. Здесь manifest — исходные JSON bytes; подпись проверяется до JSON payload decoding. `canonicalManifest(_ manifest: RuleManifest) throws -> Data` — публичная функция общего sign/verify формата.

- [ ] **Step 1: RED test — tamper never activates.** В test helper `makePackage(version:)` создать Curve25519.Signing.PrivateKey в памяти, production-valid snapshot из собственного lexicon `hello/привет`, RU↔EN mappings и protected `API`; JSONEncoder outputFormatting `[.sortedKeys, .withoutEscapingSlashes]`; SHA256 payload; manifest init с actual sizes; вернуть tuple `(manifest: Data, signature: Data, payload: Data, publicKey: Data)`. Фикстура private key не используется для release.

```swift
func testTamperedPayloadIsRejected() throws {
    let p = try makePackage(version: 2)
    var changed = p.payload
    changed[changed.startIndex] ^= 1
    let verifier = RulePackageVerifier(trustedKeys: ["test": p.publicKey], appVersion: "1.0.0")
    XCTAssertThrowsError(try verifier.verify(manifest: p.manifest,
        signature: p.signature, payload: changed, installedVersion: 1)) {
        XCTAssertEqual($0 as? RuleVerificationError, .hashMismatch)
    }
    let valid = try verifier.verify(manifest: p.manifest,
        signature: p.signature, payload: p.payload, installedVersion: 1)
    XCTAssertEqual(valid.modelVersion, 2)
}
```

- [ ] **Step 2:** `swift test --filter RulePackageVerifierTests` → RED: missing RulePackageVerifier; compilation failure acceptable only for absent planned API, не для ошибок fixture.
- [ ] **Step 3:** Реализовать canonical manifest v1 как строгий JSON из шести перечисленных полей в ASCII key-sorted порядке, без whitespace, UTF-8 string escaping, без floating-point; unknown/duplicate keys отвергать. `modelVersion/payloadSize` десятичные UInt64; не конвертировать в Double. Verify exact canonical reserialization equality. Подписываемые bytes `Data("NecarambaRules-v1\0".utf8) + canonicalManifest + Data([0]) + SHA256(payload)`; SHA256 digest в manifest lowercase hex. Ключи ограничить ASCII `[A-Za-z0-9_-]{1,64}`, app version — три неотрицательных UInt32. Ядро операции:

```swift
let digest = Data(SHA256.hash(data: payload))
let signed = Data("NecarambaRules-v1\0".utf8) + canonical + Data([0]) + digest
guard try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    .isValidSignature(signature, for: signed) else {
    throw RuleVerificationError.invalidSignature
}
```

Порядок: bounded manifest ≤64 KiB → strict manifest → trusted key/schema/app/version/size → payload digest → signature → decode/validate rules. Требовать manifest/snapshot modelVersion equality, непустые языковые lexicon/maps, лимиты строк, конечные score values из A, запрет неизвестных payload fields/schema. Нет executable scripts/paths в package. Anti-rollback: version ниже high-water отвергнуть; equal version допустима лишь при том же digest для идемпотентности. Recovery schema не реализовывать недоказанно: до отдельного signed recovery format downgrade всегда запрещён. Key rotation в v1 — app update с новым bundled public key.
- [ ] **Step 4:** Добавить fixtures invalid signature, unknown key, incompatible schema/app, size/hash mismatch, overflow UInt64, duplicate keys, malformed JSON, empty production rules, downgrade и valid max supported values; `swift test --filter RulePackageVerifierTests` → PASS, AC-054–056/058/059. Signing CLI принимает manifest/payload/private-key paths локально; секрет не пишет в log/package.
- [ ] **Step 5:** Review diff, затем **при реализации** `git add Sources/NecarambaCore/Delivery Tests/NecarambaCoreTests/Delivery Tools/Release/SignRulePackage.swift docs/release/rule-format-v1.md` и `git commit -m "feat: verify independent signed rule packages"`.

### Task 2: Offline startup, bounded download и атомарная установка

**Files:**
- Create: `Sources/NecarambaMac/Delivery/RuleDownloader.swift`, `RuleSlotStore.swift`, `RuleUpdateCoordinator.swift`, `RuleUpdateSchedule.swift`.
- Test: `Tests/NecarambaMacTests/Delivery/RuleUpdateCoordinatorTests.swift`, `RuleSlotStoreTests.swift`, `RuleUpdateScheduleTests.swift`.
- Create: `App/macos/Runner/Release/TrustedRuleKeys.json`, `App/macos/Runner/Release/BundledRules/manifest.json`, `payload.json`, `signature.ed25519`.

**Interfaces:** Consumes `RulePackageVerifier.verify(...)` и `RuleSnapshotConsumer.install(_:)`. Produces `RuleSlotStore(root: URL, verifier: RulePackageVerifier)`, `promote(_ package: RulePackage) throws -> VerifiedRuleSnapshot`, `load(bundled: RulePackage) throws -> VerifiedRuleSnapshot`. `RulePackage` — struct Sendable `{manifest:Data, signature:Data, payload:Data}`. `RuleDownloader.fetch(from: URL) async throws -> RulePackage`; `RuleUpdateCoordinator.checkNow() async` serial actor, `start() async` local-first. Coordinator сообщает `RuleUpdateStatus` enum `.idle/.checking/.current(UInt64)/.failed(String)` через AsyncStream, ошибки — reason codes без слов.

- [ ] **Step 1:** Написать failing integration test; `makePackage(version:)` из Task1 расширить возвратом RulePackage, verifier и fixture key (shared test support в `Tests/NecarambaMacTests/Delivery/RuleFixtures.swift`, не импортировать другой test target).

```swift
func testCorruptCurrentFallsBackToVerifiedPrevious() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try RuleFixtures()
    let store = RuleSlotStore(root: root, verifier: fixture.verifier)
    _ = try store.promote(fixture.package(version: 1))
    _ = try store.promote(fixture.package(version: 2))
    try Data("broken".utf8).write(to: root.appendingPathComponent("generations/2/payload.json"))
    let loaded = try store.load(bundled: fixture.package(version: 0))
    XCTAssertEqual(loaded.modelVersion, 1)
}
```

- [ ] **Step 2:** `swift test --filter RuleSlotStoreTests` → RED missing store. Fixture uses supplied runtime-generated key consistently across versions, so signature validity is not accidental.
- [ ] **Step 3:** Реализовать generation directories с immutable package bytes, fsync каждого файла и temp directory, повторной verification с диска, rename staging→generation, затем atomic rename/fsync parent одного state file `{current, previous, highestAcceptedVersion, digests}`. SQLite `model_state` из C — зеркальная UI metadata, не второй источник истины для crash recovery. Старое состояние до durable state-file swap остаётся рабочим; orphan generation cleanup только после next verified startup. Disk fault на каждом шаге оставляет целое old/new. Corrupt-current fallback читает ранее установленный previous; это не remote downgrade и high-water не уменьшает. Bundled package проверять также; при повреждении всех вариантов input pass-through, never unverified activation.

```swift
// После durable promotion, вне input executor:
let verified = try store.promote(package)
consumer.install(verified.snapshot)
// B публикует активную версию после границы транзакции.
```

Downloader использует URLSession delegate streaming: HTTPS only, allowlist одного собственного host из ReleaseConfiguration, запрет redirect на иной host/http, ephemeral configuration без cookies/credentials. Manifest ≤64KiB, signature ровно64 bytes, payload ≤20MiB на реально полученных bytes, timeout15sec, cancellation. V1 identity compression only; compressed Content-Encoding/package отвергать, а не распаковывать без контроля; абсолютный decompressed bound80MiB сохраняется для будущего формата. Не полагаться только на Content-Length. Endpoint не задан → network disabled, bundled функциональность полная. Schedule launch check и каждые24h±2h, manual throttle30sec; bounded retry через следующий scheduled cycle без tight loop. Clock/random injected `now: () -> Date`, `jitter: () -> TimeInterval` с clamp±7200sec.
- [ ] **Step 4:** `swift test --filter 'RuleSlotStoreTests|RuleUpdateCoordinatorTests|RuleUpdateScheduleTests'` → PASS для corruption/relaunch, kill points до/после state rename, timeout404/truncate/oversize/redirect/cancel, offline startup, high-water fallback, schedule/throttle. С B выполнить1000 synthetic events при swap, assert одни версии per transaction, ноль lost/reordered events (AC-053–062/101). Network fixture проверяет отсутствие слов/selection/clipboard в requests.
- [ ] **Step 5:** `git add Sources/NecarambaMac/Delivery Tests/NecarambaMacTests/Delivery App/macos/Runner/Release` и `git commit -m "feat: atomically install verified offline rule snapshots"` — только во время реализации после GREEN.

### Task 3: Explicit share-rule с preview и Cancel без сети

**Files:**
- Create: `Sources/NecarambaCore/Delivery/RuleSharePayload.swift`, `Sources/NecarambaMac/Delivery/RuleShareCoordinator.swift`, `RuleSharePreviewController.swift`.
- Test: `Tests/NecarambaMacTests/Delivery/RuleShareCoordinatorTests.swift`.

**Interfaces:** Consumes выбранное explicit слово из UI C, `Language`, active `modelVersion: UInt64`. Produces `RuleSharePayload: Codable, Equatable, Sendable` с только `word: String`, `language: Language`, `modelVersion: UInt64`, `feedback: String?`; `RuleShareTransport { func send(_ payload: RuleSharePayload) async throws }`; `@MainActor RuleShareCoordinator(transport:)` методы `preview(_:)`, `cancel()`, `confirm() async throws`. Snapshot preview immutable; изменение выбранной строки после preview не меняет payload. Confirm не доступен без preview.

- [ ] **Step 1:** Добавить spy и RED test:

```swift
actor ShareSpy: RuleShareTransport {
    private(set) var payloads: [RuleSharePayload] = []
    func send(_ payload: RuleSharePayload) async throws { payloads.append(payload) }
}
@MainActor
func testCancelNeverSends() async throws {
    let spy = ShareSpy()
    let sut = RuleShareCoordinator(transport: spy)
    sut.preview(.init(word: "синтетика", language: .russian, modelVersion: 2, feedback: nil))
    sut.cancel()
    let sent = await spy.payloads
    XCTAssertEqual(sent, [])
}
```

- [ ] **Step 2:** `swift test --filter RuleShareCoordinatorTests` → RED missing API.
- [ ] **Step 3:** Реализовать preview Flutter dialog через bridge E с видимыми четырьмя полями, собственным endpoint host и Confirm/Cancel; ни одного автоматического submit при checkbox/import/create rule. payload word валидируется NFC/trim1–20 grapheme/control ban по C; feedback ≤2000 grapheme, пустое → nil. Snapshot cleared before awaiting request предотвращает duplicate Confirm; Cancel clears. HTTPS transport ограничен собственным endpoint; отсутствие backend → unavailable, локальное исключение остаётся. Ни session/install ID, имени приложения, clipboard, окружения; не логировать body. HTTP error не запускает автоматический resend.

```swift
public func confirm() async throws {
    guard let payload = pending else { return }
    pending = nil
    try await transport.send(payload)
}
```

`pending: RuleSharePayload?` private; preview задаёт после validation, cancel устанавливает nil; конструктор сохраняет transport.
- [ ] **Step 4:** `swift test --filter RuleShareCoordinatorTests` → PASS Cancel/no-preview/duplicate confirm/selection changes/network error; JSONSerialization проверяет точное множество ключей, nil feedback отсутствует. AC-070 synthetic sentinel отсутствует в log/export/network, кроме отдельно выбранного подтверждённого payload; доступность preview/клавиатуры проверить UI C.
- [ ] **Step 5:** `git add Sources/NecarambaCore/Delivery/RuleSharePayload.swift Sources/NecarambaMac/Delivery/RuleShareCoordinator.swift Sources/NecarambaMac/Delivery/RuleSharePreviewController.swift Tests/NecarambaMacTests/Delivery/RuleShareCoordinatorTests.swift` и `git commit -m "feat: share only explicitly confirmed rule payloads"` после GREEN.

### Task 4: Собственный LicensingAdapter и отдельная коммерческая фаза

**Files:**
- Create: `Sources/NecarambaCore/Licensing/EntitlementState.swift`, `LicensingAdapter.swift`, `LocalEntitlementProvider.swift`, `EntitlementPolicy.swift`.
- Create: `Sources/NecarambaMac/Licensing/StoreKitLicensingAdapter.swift`, `VerifiedEntitlementCache.swift`.
- Test: `Tests/NecarambaCoreTests/Licensing/EntitlementPolicyTests.swift`, `Tests/NecarambaMacTests/Licensing/StoreKitLicensingAdapterTests.swift`.
- Create: `App/macos/Runner/Release/Commercial.storekit`, `docs/release/commercial-policy.md`.

**Interfaces:** Produces:

```swift
public enum EntitlementState: Equatable, Sendable {
    case checking, trial(until: Date), active(until: Date?, renews: Bool)
    case grace(until: Date), pending, expired, revoked, unavailable
}
public protocol LicensingAdapter {
    func current() async -> EntitlementState
    func purchase(productID: String) async throws -> PurchaseOutcome
    func restore() async throws -> EntitlementState
}
public enum PurchaseOutcome: Equatable, Sendable {
    case entitled(EntitlementState), cancelled, pending
}
```

C получает state на main actor, B получает только policy на границе transaction; transition никогда не прерывает applying edit. `LocalEntitlementProvider(.active(until:nil, renews:false))` — только internal prototype compile configuration. Free release и commercial release отдельны; окончательный бизнес-выбор владельца фиксируется до release. Собственные TeamID/ProductIDs/backend — обязательные release inputs, их отсутствие блокирует коммерческий release, но не basic input.

- [ ] **Step 1:** RED test exact expiry/offline behavior. `EntitlementPolicy.allowsPaidFeatures(state:now:) -> Bool`; ограниченная offline policy для proposed commercial phase — max72h после last verified, никогда дальше signed entitlement expiry; UI показывает deadline. Это собственное решение для согласования, не свойство эталона.

```swift
func testGraceExpiresAtBoundary() {
    let deadline = Date(timeIntervalSince1970: 10_000)
    XCTAssertTrue(EntitlementPolicy.allowsPaidFeatures(
        state: .grace(until: deadline), now: deadline.addingTimeInterval(-1)))
    XCTAssertFalse(EntitlementPolicy.allowsPaidFeatures(
        state: .grace(until: deadline), now: deadline))
    XCTAssertFalse(EntitlementPolicy.allowsPaidFeatures(state: .pending, now: deadline))
}
```

- [ ] **Step 2:** `swift test --filter EntitlementPolicyTests` → RED missing policy.
- [ ] **Step 3:** Implement pure state policy; active(nil) разрешено только выбранному free/development provider, commercial active требует verified product policy. StoreKit wrapper использует собственный configured product allowlist, `Product.purchase`, `Transaction.currentEntitlements/updates`, only `.verified`, проверяет productID/bundle/environment, expiration/revocation. `.userCancelled` → `.cancelled`, `.pending` не создаёт paid entitlement; prior verified entitlement сохраняется согласно policy. `AppStore.sync()` только restore button. Кэш хранит signed verification material/checked dates в собственном Keychain, не boolean; повторная signature verification на load, неизвестный/повреждённый кэш unavailable. Clock rollback → unavailable/online verification, не продление grace. Отдельный actor serializes updates.

```swift
switch state {
case .active(let until, _): return until.map { now < $0 } ?? true
case .trial(let until), .grace(let until): return now < until
case .checking, .pending, .expired, .revoked, .unavailable: return false
}
```

Commercial.storekit содержит только свои локальные тестовые IDs под явно test namespace; release config validator отвергает test values. Чужие receipts, service URLs, product IDs, аккаунты и bundle IDs не переиспользуются. Полный network/backend licensing protocol вне этого client plan; никакой зависимости local input от его существования.
- [ ] **Step 4:** `swift test --filter EntitlementPolicyTests` → PASS; `xcodebuild test -workspace App/macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -only-testing:NecarambaMacTests/StoreKitLicensingAdapterTests` → PASS в local StoreKit configuration для verified/unverified/pending/cancel/restore/expiry/revocation/offline/clock rollback. AC-086–090 только после выбранного commercial режима; free получает N/A с явным решением, не фиктивный PASS. Сделать integration test expired mid-edit: завершение безопасной транзакции, изменение последующей policy, нет удаления данных.
- [ ] **Step 5:** `git add Sources/NecarambaCore/Licensing Sources/NecarambaMac/Licensing Tests/NecarambaCoreTests/Licensing Tests/NecarambaMacTests/Licensing App/macos/Runner/Release/Commercial.storekit docs/release/commercial-policy.md` и `git commit -m "feat: isolate own entitlement and optional StoreKit flow"` после GREEN.

### Task 5: Universal Developer ID release, notarization, MAS feasibility и compatibility gate

**Files:**
- Create: `Sources/NecarambaCore/Delivery/ReleaseGate.swift`.
- Create: `App/macos/Runner/Release/DeveloperID.xcconfig`, `MAS.xcconfig`, `DeveloperID.entitlements`, `MAS.entitlements`, `ExportOptions.plist`.
- Create: `Tools/Release/verify-artifact.sh`, `validate-release-report.swift`, `docs/release/release-inputs.md`, `compatibility-manifest.json`, `release-report.json`, `mas-feasibility.md`.
- Test: `Tests/NecarambaCoreTests/Delivery/ReleaseGateTests.swift`.
- Integration-only Modify: `App/macos/Runner.xcodeproj/project.pbxproj` — интегратор добавляет configurations/test StoreKit setting, scheme `Runner`.

**Interfaces:** `ReleaseGate.isReady(required:Set<String>, results:[String:AcceptanceResult]) -> Bool`; `AcceptanceResult` Codable `{status: AcceptanceStatus, evidencePath:String, buildSHA:String, architecture:String, osBuild:String}`; enum `.passed/.failed/.unrun/.notApplicable`. Required commercial set зависит от явно выбранного канала; N/A не заменяет mandatory PASS. `validate-release-report.swift` читает только собственный JSON, exit0 ready/exit1 failed или missing evidence.

- [ ] **Step 1:** RED release gate test:

```swift
func testMissingCompatibilityResultBlocksRelease() {
    XCTAssertFalse(ReleaseGate.isReady(required: ["AC-091", "AC-092"], results: [:]))
    let failed = AcceptanceResult(status: .failed, evidencePath: "evidence/intel.json",
        buildSHA: "fixture", architecture: "x86_64", osBuild: "fixture")
    XCTAssertFalse(ReleaseGate.isReady(required: ["AC-092"], results: ["AC-092": failed]))
}
```

- [ ] **Step 2:** `swift test --filter ReleaseGateTests` → RED missing gate.
- [ ] **Step 3:** Реализовать validator и configs: `MACOSX_DEPLOYMENT_TARGET=12.0`, `ARCHS=arm64 x86_64`, `ONLY_ACTIVE_ARCH=NO`, `ENABLE_HARDENED_RUNTIME=YES`, `SWIFT_VERSION=5.0`; не отключать library validation/защиты без конкретной необходимости. Runtime release inputs: own Apple Team ID, own bundle IDs/helper IDs, Developer ID certificate/profile, notarytool Keychain profile, own public signing keys/rule endpoint, support/privacy URLs; commercial ещё own ProductIDs и approved policy. Release script завершает с ошибкой при пустых/test inputs. Secrets не в Git. `verify-artifact.sh` проверяет **каждый** Mach-O main/helper/framework, обе slices, minOS≤12, подписи nested inside-out, entitlements; не использовать `codesign --deep` как способ подписать неизвестное дерево. MAS конфигурация включает sandbox/network only needed capabilities, свой канал без Developer ID updater; capability feasibility доказать signed sandbox build, не переносить broad entitlements из сторонних приложений.

```swift
return required.allSatisfy { id in
    guard let result = results[id] else { return false }
    return result.status == .passed && !result.evidencePath.isEmpty
        && !result.buildSHA.isEmpty && !result.architecture.isEmpty && !result.osBuild.isEmpty
}
```

Gate дополнительно проверяет существование evidence и матрицу host tuples; одного AC ID недостаточно для двух архитектур. JSON report индексировать `AC-ID/arch/OS/app/adapter`, required keys генерировать из утверждённого compatibility manifest. Простая функция выше проверяет только inner result set; wrapper разворачивает tuples, не принимает один arm64 PASS за Intel.
- [ ] **Step 4:** `swift test --filter ReleaseGateTests` → PASS missing/failed/unrun/empty evidence/N/A mandatory blocked. Затем выполнить release commands только при наличии own release inputs:

```bash
(cd App && flutter build macos --release)
xcodebuild archive -workspace App/macos/Runner.xcworkspace -scheme Runner -configuration DeveloperID -archivePath build/Necaramba.xcarchive 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
xcodebuild -exportArchive -archivePath build/Necaramba.xcarchive -exportPath build/export -exportOptionsPlist App/macos/Runner/Release/ExportOptions.plist
Tools/Release/verify-artifact.sh build/export/Necaramba.app
ditto -c -k --keepParent build/export/Necaramba.app build/Necaramba.zip
xcrun notarytool submit build/Necaramba.zip --keychain-profile "$NECARAMBA_NOTARY_PROFILE" --wait
xcrun stapler staple build/export/Necaramba.app
xcrun stapler validate build/export/Necaramba.app
codesign --verify --strict --verbose=2 build/export/Necaramba.app
spctl --assess --type execute --verbose=2 build/export/Necaramba.app
```

Ожидания: archive/export exit0; all required executable slices arm64/x86_64; notary status Accepted, stapler valid, codesign valid, spctl accepted. После stapling пересоздать финальный zip и заново verify его extracted app. Проверить **скачанный quarantined финальный artifact** на чистом Mac; local spctl одного пути не заменяет этот gate. Не публиковать из этой задачи без отдельного release решения владельца.

- [ ] **Step 5:** Заполнить compatibility manifest фактическими build SHA/model hash/OS/app/adapter, AC-091–103, E-01–E-04 и mandatory functional AC: native Intel/macOS12 обязателен, Apple Silicon/macOS12+, macOS13 login path, текущие supported OS; TextEdit/Safari/Chromium/Electron, Terminal/IDE auto-deny до квалификации. Работы B/C дают tests/evidence, D не присваивает PASS по факту компиляции. Зафиксировать p99tap≤2ms, classifier≤10ms, idle≤0.5%, RSS≤100MiB без engine / ≤200MiB с Flutter UI, E4 и zero corruption/reordered/lost/duplicate100000 replay; gates качества A AC-022 обязательны. MAS separate gate AC-096: real sandbox listen/post/TIS/focus/selection/signing, clean user; отказ API → MAS blocked, DeveloperID может пройти собственные gates. Перед выпуском проверить актуальные Apple docs/Review Guidelines и приложить дату/source к `mas-feasibility.md`.
- [ ] **Step 6:** `swift Tools/Release/validate-release-report.swift docs/release/release-report.json` → exit0 только при всех required tuples PASS и legal N/A для optional scope. `git add Sources/NecarambaCore/Delivery/ReleaseGate.swift App/macos/Runner/Release Tools/Release docs/release Tests/NecarambaCoreTests/Delivery/ReleaseGateTests.swift` и `git commit -m "build: gate universal signed releases on measured compatibility"` после GREEN; project diff добавляет только интегратор.

## Проверка покрытия и handoff

Task1–2: F12, AC-053–062/101; Task3: F22 и AC-070; Task4: F20, AC-086–090; Task5: AC-091–103, aggregation остальных mandatory AC из A/B/C. App binary auto-update channel — Developer ID release artifact с собственной подписью и отдельным release pipeline; клиентская автоустановка приложения не является подтверждённым обязательным сценарием исследования, поэтому здесь не добавляется произвольный executable downloader. Background **rule** updates обязательны и покрыты Task2.

Выполнение не начато. После утверждения спецификации доступны subagent-driven-development (по задаче с review) либо executing-plans в одной сессии. Этот документ не даёт оснований заявлять полный аналог, пока mandatory AC остаются unrun.

Flutter integration: D services и StoreKit остаются Swift; все paywall/share/freshness UI — Flutter через E. RunnerTests подключаются интегратором к scheme Runner вместе с NecarambaMacTests. Release configurations DeveloperID/MAS наследуют Flutter release xcconfig/build phases; иначе Flutter assets/AOT frameworks не попадут в archive. D5 проверяет архитектуры и deployment targets всех вложенных engine/plugins, а не только основного executable.
