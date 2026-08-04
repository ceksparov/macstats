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


/// Bir sensörün hangi bileşene ait olduğu.
public enum SensörGrubu: Sendable {
    case işlemciÇekirdeği
    case çipGövdesi
    case grafik
    case pil
    case depolama
}

/// Sensör adına bakarak hangi bileşene ait olduğunu tahmin eder.
///
/// BAŞKA MAC MODELLERİ İÇİN EN ÖNEMLİ YER BURASI. Sensör isimleri Apple'ın
/// belgelemediği, çipe göre değişen isimler. Bu M1 Air'de çekirdekler
/// "pACC"/"eACC" diye adlandırılmış; başka bir çipte farklı olabilir.
/// O yüzden:
///   - eşleşme tam isimle değil önekle yapılıyor (sensör numaraları değişiyor),
///   - birden fazla bilinen adlandırma birden deneniyor,
///   - hiçbiri tutmazsa çip gövdesi sensörleri işlemci yerine kullanılıyor
///     (bkz. Sıcaklıklar.işlemci) — kabaca doğru bir sayı, hiç sayı olmamasından iyi.
///
/// Tanımadığımız bir sensör nil döner ve hiçbir yerde kullanılmaz.
public func sensörGrubu(_ isim: String) -> SensörGrubu? {
    // Apple Silicon çekirdek sensörleri: p = performans, e = verimlilik.
    if isim.hasPrefix("pACC") || isim.hasPrefix("eACC") { return .işlemciÇekirdeği }
    // Bazı modellerde çekirdek sensörleri doğrudan "CPU" diye geçiyor.
    if isim.hasPrefix("CPU") { return .işlemciÇekirdeği }

    if isim.hasPrefix("GPU") { return .grafik }
    if isim.hasPrefix("SOC MTR") || isim.hasPrefix("PMGR SOC") { return .çipGövdesi }
    // "PMU tdie" güç biriminin ölçtüğü çip sıcaklığı; çekirdek sensörü
    // bulunamayan modellerde tek dayanağımız bu olabilir.
    if isim.hasPrefix("PMU tdie") || isim.hasPrefix("PMU2 tdie") { return .çipGövdesi }

    if isim.contains("battery") { return .pil }
    if isim.hasPrefix("NAND") || isim.hasPrefix("SSD") { return .depolama }

    // Tanımadıklarımız: kalibrasyon referansları (PMU tcal), bağlı olmayan
    // soketler (PMU tdev), ekran/kamera sensörleri...
    return nil
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

    /// Grup olarak "işlemci çekirdeği" diye tanınan bütün sensörlerin en
    /// yükseği. hızlıÇekirdekler/verimliÇekirdekler bu Mac'in adlandırmasına
    /// özel; bu alan model bağımsız çalışır.
    public let çekirdekler: Double?

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
    /// Başka Mac modellerinde çekirdek sensörü hiç bulunamayabilir; o durumda
    /// çip gövdesi sıcaklığına düşüyoruz. Birebir aynı şey değil ama birkaç
    /// derece yakınında ve "hiç sayı yok"tan iyi.
    public var işlemci: Double? {
        [hızlıÇekirdekler, verimliÇekirdekler, çekirdekler]
            .compactMap { $0 }.max() ?? çipGövdesi
    }
}


// MARK: - Okuyucu

public final class SıcaklıkOkuyucu {

    /// Sisteme açtığımız sensör bağlantısı. Her ölçümde yeniden açmak pahalı
    /// olurdu, o yüzden bir kere açıp saklıyoruz.
    private var istemci: AnyObject?

    /// Bağlantı bir kere kurulamadıysa her saniye tekrar denemenin anlamı yok.
    private var kurulumBaşarısız = false

    /// true ise hiçbir eleme yapılmaz, bütün sensörler okunur (tanı aracı).
    private let hepsiniOku: Bool

    /// İlk okumada keşfedilip saklanan sensörler, hangi gruba ait olduklarıyla
    /// birlikte. İsimleri de burada duruyor: sensörün adını her ölçümde
    /// yeniden sormak boşuna iş, isimler çalışma boyunca değişmiyor.
    private var seçilmişSensörler: [(servis: AnyObject, isim: String, grup: SensörGrubu?)]?

    public init(hepsiniOku: Bool = false) {
        self.hepsiniOku = hepsiniOku
    }

    /// Uykudan uyanma sonrası çağrılmalı: uyku boyunca bağlantı ölmüş olabilir
    /// ve ölü bağlantı hata vermez, sadece eski değeri döndürmeye devam eder.
    /// Bunu yaşamadan fark etmek zor olduğu için baştan koyuyoruz.
    public func bağlantıyıYenile() {
        istemci = nil
        seçilmişSensörler = nil
        kurulumBaşarısız = false
    }

    /// Bütün sıcaklıkları okur. Okuyamazsa nil döner.
    public func oku() -> Sıcaklıklar? {
        guard let sensörler = sensörleriGetir(), let olayOku, let ondalıkDeğerAl
        else { return nil }

        var okumalar: [SensörOkuması] = []
        for sensör in sensörler {
            // Son iki parametre ayar bayrakları ve zaman damgası; ikisi de 0 =
            // "varsayılan ayarlarla, şu anki değeri ver".
            guard let olay = olayOku(sensör.servis, sıcaklıkOlayTürü, 0, 0)?.takeRetainedValue()
            else { continue }  // Bu sensör şu an değer vermiyor.

            let derece = ondalıkDeğerAl(olay, sıcaklıkDeğerAlanı)
            guard makulAralık.contains(derece) else { continue }

            okumalar.append(SensörOkuması(isim: sensör.isim, derece: derece))
        }

        guard !okumalar.isEmpty else {
            // Hiçbiri cevap vermiyorsa saklanan liste bayatlamış olabilir
            // (uyku, donanım değişikliği). Bir dahakine sıfırdan tarasın.
            seçilmişSensörler = nil
            return nil
        }
        return Sıcaklıklar(
            hızlıÇekirdekler:   enYüksek(okumalar, öneki: "pACC"),
            verimliÇekirdekler: enYüksek(okumalar, öneki: "eACC"),
            grafik:             enYüksek(okumalar, grubu: .grafik),
            çipGövdesi:         enYüksek(okumalar, grubu: .çipGövdesi),
            pil:                enYüksek(okumalar, grubu: .pil),
            depolama:           enYüksek(okumalar, grubu: .depolama),
            çekirdekler:        enYüksek(okumalar, grubu: .işlemciÇekirdeği),
            hamOkumalar:        okumalar
        )
    }

    /// İlgilendiğimiz sensörleri verir. Liste ilk çağrıda bir kez kurulur,
    /// sonraki ölçümler doğrudan onu kullanır.
    private func sensörleriGetir() -> [(servis: AnyObject, isim: String, grup: SensörGrubu?)]? {
        if let seçilmişSensörler { return seçilmişSensörler }
        guard !kurulumBaşarısız, let özellikOku else { return nil }

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

        guard let istemci, let servisleriAl,
              let hepsi = servisleriAl(istemci)?.takeRetainedValue() as? [AnyObject]
        else { return nil }

        // İsimleri burada, bir kereye mahsus okuyoruz. Sensör adları çalışma
        // boyunca değişmiyor; her ölçümde yeniden sormak boşa giden süreydi.
        var seçilmiş: [(servis: AnyObject, isim: String, grup: SensörGrubu?)] = []
        for servis in hepsi {
            let isim = (özellikOku(servis, "Product" as CFString)?
                .takeRetainedValue() as? String) ?? "(isimsiz)"
            let grup = sensörGrubu(isim)
            // Tanımadığımız sensörleri her ölçümde okumanın anlamı yok; bu
            // makinede 57 sensörün hepsini okumak 55 ms, tanıdıklar 3.7 ms.
            if !hepsiniOku && grup == nil { continue }
            seçilmiş.append((servis, isim, grup))
        }

        guard !seçilmiş.isEmpty else { return nil }
        seçilmişSensörler = seçilmiş
        return seçilmiş
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

/// Bir gruba ait sensörlerin en yükseğini bulur.
public func enYüksek(_ okumalar: [SensörOkuması], grubu: SensörGrubu) -> Double? {
    okumalar
        .filter { sensörGrubu($0.isim) == grubu }
        .map(\.derece)
        .max()
}
