import Foundation

// ============================================================================
// SICAKLIK OKUMA
//
// Apple, M1 çiplerinde sıcaklık sensörlerini uygulamalara resmî olarak
// açmıyor. Sensörleri okuyan fonksiyonlar işletim sisteminin içinde (IOKit)
// var, ama belgelenmedikleri için derleyicinin bakabileceği bir tanım dosyası
// yok — normal yoldan çağıramıyoruz.
//
// Çözüm: IOKit'i çalışma anında açıp (dlopen) ihtiyacımız olan fonksiyonları
// isimleriyle arıyoruz (dlsym). Bulursak kullanıyoruz, bulamazsak uygulama
// çökmüyor; sadece sıcaklık yerine "—" gösteriyoruz.
//
// BU DOSYA UYGULAMANIN TEK KIRILGAN YERİ. Apple bir gün bunu değiştirirse
// sadece burası bozulur; işlemci ve bellek ölçümleri resmî API kullandığı
// için etkilenmez. Bilerek böyle ayırdık.
// ============================================================================


// MARK: - IOKit'i açma ve fonksiyonları elle bulma

private let ioKitYolu = "/System/Library/Frameworks/IOKit.framework/IOKit"

// RTLD_LAZY: fonksiyonları hemen değil, ilk kullanıldıklarında çözümle.
private let ioKit = dlopen(ioKitYolu, RTLD_LAZY)

/// IOKit içinde bir fonksiyonu ismiyle arar ve çağrılabilir hâle getirir.
/// Bulamazsa nil döner — bu bir çökme sebebi değil, "bu macOS sürümünde yok" demek.
private func ioKitFonksiyonu<T>(_ isim: String, _ tip: T.Type) -> T? {
    guard let ioKit, let adres = dlsym(ioKit, isim) else { return nil }
    return unsafeBitCast(adres, to: tip)
}

// Aradığımız fonksiyonların imzaları: kaç parametre alıp ne döndürdükleri.
// @convention(c)  = "bu bir C fonksiyonu"
// Unmanaged<...>  = "belleğini Swift değil biz yöneteceğiz"
private typealias İstemciOluşturTipi = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
private typealias FiltreAyarlaTipi   = @convention(c) (AnyObject, CFDictionary) -> Void
private typealias ServisleriAlTipi   = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
private typealias ÖzellikOkuTipi     = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
private typealias OlayOkuTipi        = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
private typealias OndalıkDeğerAlTipi = @convention(c) (AnyObject, Int32) -> Double

private let istemciOluştur = ioKitFonksiyonu("IOHIDEventSystemClientCreate", İstemciOluşturTipi.self)
private let filtreAyarla   = ioKitFonksiyonu("IOHIDEventSystemClientSetMatching", FiltreAyarlaTipi.self)
private let servisleriAl   = ioKitFonksiyonu("IOHIDEventSystemClientCopyServices", ServisleriAlTipi.self)
private let özellikOku     = ioKitFonksiyonu("IOHIDServiceClientCopyProperty", ÖzellikOkuTipi.self)
private let olayOku        = ioKitFonksiyonu("IOHIDServiceClientCopyEvent", OlayOkuTipi.self)
private let ondalıkDeğerAl = ioKitFonksiyonu("IOHIDEventGetFloatValue", OndalıkDeğerAlTipi.self)


// MARK: - Sabitler

// Apple kendi donanım sensörlerini "üretici tanımlı" bir grup altında topluyor.
// 0xff00 bu grubun numarası, 5 ise grup içinde "sıcaklık sensörü" demek.
private let appleSensörGrubu    = 0xff00
private let sıcaklıkSensörüTürü = 5

// Sensörden okurken hangi tür ölçüm istediğimizi söylüyoruz: 15 = sıcaklık.
// Değerin durduğu alanın numarası ise türün 16 bit sola kaydırılmışı;
// bu IOKit'in kendi adresleme kuralı.
private let sıcaklıkOlayTürü  : Int64 = 15
private let sıcaklıkDeğerAlanı: Int32 = 15 << 16

// Makul sıcaklık aralığı. Bu Mac'te bağlı olmayan bazı sensör soketleri
// -22 °C gibi anlamsız değerler üretiyor (PMU tdev1, tdev2, tdev6). Bunları
// göstermek yanlış bilgi vermek olur, o yüzden aralık dışını atıyoruz.
private let makulAralık = -10.0 ... 130.0


// MARK: - Veri tipleri

/// Tek bir sensörün o anki okuması.
public struct SensörOkuması: Sendable {
    public let isim: String
    public let derece: Double
}

/// Bir ölçüm anındaki bütün sıcaklıklar, işe yarar şekilde gruplanmış hâlde.
/// Alanların nil olabilmesi bilinçli: sensör yoksa sıfır değil "bilinmiyor"
/// göstermek istiyoruz.
public struct Sıcaklıklar: Sendable {
    public let hızlıÇekirdekler: Double?    // pACC — performans çekirdekleri
    public let verimliÇekirdekler: Double?  // eACC — verimlilik çekirdekleri
    public let grafik: Double?              // GPU
    public let çipGövdesi: Double?          // SOC / PMGR
    public let pil: Double?
    public let depolama: Double?            // NAND (SSD)

    /// Tanı amaçlı ham liste. Menü barda kullanılmıyor, sensör isimleri
    /// başka bir modelde değişirse buraya bakacağız.
    public let hamOkumalar: [SensörOkuması]

    /// Uygulamanın "işlemci sıcaklığı" olarak gösterdiği değer:
    /// çekirdek sensörlerinin en yükseği.
    ///
    /// Neden en yükseği: çipin farklı köşeleri farklı sıcaklıkta ve aynı anda
    /// 7 ayrı çekirdek sensörü farklı değer veriyor. Ortalama alsak asıl
    /// kızışan noktayı gizlerdik; seni ilgilendiren zaten en sıcak nokta.
    ///
    /// Neden bütün sensörlerin değil sadece çekirdeklerin en yükseği: "PMU
    /// tcal" gibi sensörler sıcaklık değil kalibrasyon referansı taşıyor ve
    /// sabit 51.9 °C veriyor. Hepsini karıştırsak makine buz gibiyken de
    /// yanarken de aynı sayıyı gösterirdik.
    public var işlemci: Double? {
        [hızlıÇekirdekler, verimliÇekirdekler].compactMap { $0 }.max()
    }
}


// MARK: - Okuyucu

public final class SıcaklıkOkuyucu {

    /// Sisteme açtığımız sensör bağlantısı. Her ölçümde yeniden açmak pahalı
    /// olurdu, o yüzden bir kere açıp saklıyoruz.
    private var istemci: AnyObject?

    /// Bağlantı bir kere kurulamadıysa her saniye tekrar denemenin anlamı yok.
    private var kurulumBaşarısız = false

    public init() {}

    /// Uykudan uyanma sonrası çağrılmalı: uyku boyunca bağlantı ölmüş olabilir
    /// ve ölü bağlantı hata vermez, sadece eski değeri döndürmeye devam eder.
    /// Bunu yaşamadan fark etmek zor olduğu için baştan koyuyoruz.
    public func bağlantıyıYenile() {
        istemci = nil
        kurulumBaşarısız = false
    }

    /// Bütün sıcaklıkları okur. Okuyamazsa nil döner.
    public func oku() -> Sıcaklıklar? {
        guard let servisler = servisleriGetir() else { return nil }

        var okumalar: [SensörOkuması] = []
        for servis in servisler {
            guard let özellikOku, let olayOku, let ondalıkDeğerAl else { break }

            let isim = (özellikOku(servis, "Product" as CFString)?
                .takeRetainedValue() as? String) ?? "(isimsiz)"

            // Son iki parametre ayar bayrakları ve zaman damgası; ikisi de 0 =
            // "varsayılan ayarlarla, şu anki değeri ver".
            guard let olay = olayOku(servis, sıcaklıkOlayTürü, 0, 0)?.takeRetainedValue()
            else { continue }  // Bu sensör şu an değer vermiyor.

            let derece = ondalıkDeğerAl(olay, sıcaklıkDeğerAlanı)
            guard makulAralık.contains(derece) else { continue }

            okumalar.append(SensörOkuması(isim: isim, derece: derece))
        }

        guard !okumalar.isEmpty else { return nil }
        return Sıcaklıklar(
            hızlıÇekirdekler:   enYüksek(okumalar, öneki: "pACC"),
            verimliÇekirdekler: enYüksek(okumalar, öneki: "eACC"),
            grafik:             enYüksek(okumalar, öneki: "GPU"),
            çipGövdesi:         enYüksek(okumalar, önekleri: ["SOC MTR", "PMGR SOC"]),
            pil:                enYüksek(okumalar, öneki: "gas gauge battery"),
            depolama:           enYüksek(okumalar, öneki: "NAND"),
            hamOkumalar:        okumalar
        )
    }

    /// Sensör bağlantısını (gerekiyorsa açarak) kullanır ve sensör listesini verir.
    private func servisleriGetir() -> [AnyObject]? {
        guard !kurulumBaşarısız else { return nil }

        if istemci == nil {
            guard let istemciOluştur, let filtreAyarla,
                  let yeni = istemciOluştur(kCFAllocatorDefault)?.takeRetainedValue()
            else {
                kurulumBaşarısız = true
                return nil
            }
            // Sadece sıcaklık sensörleri gelsin diye filtre koyuyoruz; yoksa
            // sistemdeki her HID aygıtı (klavye, trackpad...) listeye düşer.
            let filtre: [String: Int] = [
                "PrimaryUsagePage": appleSensörGrubu,
                "PrimaryUsage": sıcaklıkSensörüTürü,
            ]
            filtreAyarla(yeni, filtre as CFDictionary)
            istemci = yeni
        }

        guard let istemci, let servisleriAl else { return nil }
        return servisleriAl(istemci)?.takeRetainedValue() as? [AnyObject]
    }
}


// MARK: - Yardımcılar

/// İsmi verilen önekle başlayan sensörlerin en yükseğini bulur.
/// Tam isim yerine önek eşliyoruz, çünkü sensör numaraları ("pACC MTR Temp
/// Sensor3") Mac modeline ve macOS sürümüne göre değişiyor.
func enYüksek(_ okumalar: [SensörOkuması], öneki: String) -> Double? {
    enYüksek(okumalar, önekleri: [öneki])
}

func enYüksek(_ okumalar: [SensörOkuması], önekleri: [String]) -> Double? {
    okumalar
        .filter { okuma in önekleri.contains { okuma.isim.hasPrefix($0) } }
        .map(\.derece)
        .max()
}
