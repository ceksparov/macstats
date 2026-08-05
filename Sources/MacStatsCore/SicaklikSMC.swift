import Foundation
import IOKit

// ============================================================================
// INTEL MAC'LER İÇİN SICAKLIK — SMC
//
// Apple Silicon'da sensörleri IOHID üzerinden okuyoruz (Sicaklik.swift).
// Intel Mac'lerde o sistem yok; sıcaklıklar SMC (System Management Controller)
// denen ayrı bir yongadan okunuyor. Bu dosya sadece o durumda devreye giriyor:
// IOHID hiçbir şey döndürmezse buraya düşülüyor.
//
// SMC de belgelenmemiş bir arayüz — IOHID'den bile eski ve daha çok bilinen
// bir yöntem (smcFanControl, iStat gibi araçlar yıllardır bunu kullanıyor).
// Kök yetkisi gerektirmiyor.
//
// Yapı boyutu doğrulandı: SMCVeri tam 80 bayt olmalı (aşağıdaki dolgu alanına
// bakınız). Bu tutmazsa çekirdek çağrıyı reddediyor.
//
// Sıcaklık anahtarları (TC0P, TC0D, TG0D) github.com/jkuri/macstats ile
// çapraz doğrulandı — 2015'ten beri gerçek Intel Mac'lerde çalışan, bağımsız
// bir projede birebir aynı anahtarlar kullanılıyor.
//
// !!! AMA BU KOD HÂLÂ GERÇEK INTEL DONANIMINDA ÇALIŞTIRILMADI !!!
// Anahtarların doğruluğu bir referansla teyit edildi, ama SMC çağrı
// protokolünün (yapı boyutu, komut numaraları, veri çözme) bu makinede
// gerçekten çalıştığı hiç görülmedi — elimizde Intel Mac yok. Bu yüzden
// kesinlikle YEDEK yol olarak duruyor: Apple Silicon'da hiç çalıştırılmıyor,
// dolayısıyla çalışan tarafı bozamaz. Bir Intel Mac'te denenene kadar
// "anahtarlar doğru, protokol muhtemelen çalışır" muamelesi görmeli.
// ============================================================================


// MARK: - SMC'nin beklediği veri yapısı
//
// Alan sırası ve tipleri SMC sürücüsünün beklediğiyle birebir aynı olmak
// zorunda; tek bir alan kayarsa okuma anlamsız değerler döner.

private struct SMCSürüm {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCGüçSınırı {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCAnahtarBilgisi {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    /// C derleyicisinin son alandan sonra eklediği hizalama boşluğu.
    /// Swift bu boşluğu kendiliğinden eklemiyor, sonraki alanları içine
    /// kaydırıyor. Elle koymazsak yapının tamamı 80 yerine 76 bayt oluyor ve
    /// çekirdek çağrıyı boyut yüzünden reddediyor — ölçüldü, doğrulandı.
    var dolgu: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private struct SMCVeri {
    var key: UInt32 = 0
    var vers = SMCSürüm()
    var pLimitData = SMCGüçSınırı()
    var keyInfo = SMCAnahtarBilgisi()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

// SMC sürücüsüne gönderilen komut numaraları.
private let smcİşlevNo: UInt32 = 2   // "SMC olayını işle"
private let smcOku: UInt8 = 5        // anahtarın değerini oku
private let smcBilgiOku: UInt8 = 9   // anahtarın türünü ve boyutunu oku

/// "TC0P" gibi dört harfli anahtarı SMC'nin beklediği sayıya çevirir.
private func anahtarNumarası(_ anahtar: String) -> UInt32 {
    var sonuç: UInt32 = 0
    for karakter in anahtar.utf8.prefix(4) {
        sonuç = (sonuç << 8) | UInt32(karakter)
    }
    return sonuç
}

/// Veri türü etiketleri de dört harfli: "sp78", "flt ".
private let türSP78 = anahtarNumarası("sp78")
private let türFLT  = anahtarNumarası("flt ")


// MARK: - Okuyucu

final class SMCOkuyucu {

    /// Intel Mac'lerde bilinen sıcaklık anahtarları, gruplarıyla.
    ///
    /// Bu üç anahtar (TC0P, TC0D, TG0D) jkuri/macstats projesiyle çapraz
    /// doğrulandı — 2015'ten beri gerçek Intel Mac'lerde çalışan, 70+ yıldız
    /// almış bağımsız bir projenin kodunda birebir aynı anahtarlar kullanılıyor.
    /// (github.com/jkuri/macstats, smc/smc.cc — SMCGetTemperature() ve
    /// CpuTemperatureDie()/GpuTemperature() fonksiyonları.)
    ///
    /// Önceki sürümde burada 10 anahtar daha vardı (TC0E, TC0F, TCXC, TG0P,
    /// TB0T/TB1T/TB2T, TH0P, Ts0P, TA0P) — hepsi benim tahminimdi, hiçbiri
    /// hiçbir kaynakta doğrulanamadı. Kaldırıldılar: doğrulanmamış bir anahtarı
    /// listede tutmak "belki tutar" diye umut etmekten ibaretti, ki bu
    /// projenin "yanlış sayı göstermektense hiç gösterme" ilkesine aykırı.
    /// Pil sıcaklığı artık SMC tahminine değil, aşağıdaki
    /// pilSıcaklığınıOku()'daki IORegistry okumasına dayanıyor.
    private static let anahtarlar: [(anahtar: String, grup: SensörGrubu, ad: String)] = [
        ("TC0P", .işlemciÇekirdeği, "CPU proximity"),
        ("TC0D", .işlemciÇekirdeği, "CPU die"),
        ("TG0D", .grafik, "GPU die"),
    ]

    private var bağlantı: io_connect_t = 0
    private var denendi = false

    deinit {
        if bağlantı != 0 { IOServiceClose(bağlantı) }
    }

    /// SMC'den okunabilen bütün sıcaklıkları verir. Bu makinede SMC yoksa ya da
    /// hiçbir anahtar cevap vermiyorsa boş liste döner.
    func oku() -> [SensörOkuması] {
        guard bağlan() else { return [] }

        var okumalar: [SensörOkuması] = []
        for aday in Self.anahtarlar {
            guard let derece = değerOku(aday.anahtar) else { continue }
            // IOHID tarafındaki gruplamayı burada isimle taklit edemeyiz
            // (anahtarlar "TC0D" gibi), o yüzden okunabilir bir ad veriyoruz.
            guard (-10.0 ... 130.0).contains(derece) else { continue }
            okumalar.append(SensörOkuması(isim: aday.ad, derece: derece))
        }
        if let pil = pilSıcaklığınıOku() {
            okumalar.append(SensörOkuması(isim: "Battery (IORegistry)", derece: pil))
        }
        return okumalar
    }

    /// Grup bazında en yüksek değerleri verir — Sıcaklıklar'ı kurmak için.
    func gruplaraGöre() -> [SensörGrubu: Double] {
        guard bağlan() else { return [:] }

        var sonuç: [SensörGrubu: Double] = [:]
        for aday in Self.anahtarlar {
            guard let derece = değerOku(aday.anahtar),
                  (-10.0 ... 130.0).contains(derece) else { continue }
            sonuç[aday.grup] = max(sonuç[aday.grup] ?? -Double.infinity, derece)
        }
        if let pil = pilSıcaklığınıOku() {
            sonuç[.pil] = pil
        }
        return sonuç
    }

    /// Pil sıcaklığını SMC'den TAHMİN ETMEK yerine IORegistry'den okur.
    /// AppleSmartBattery servisi Intel ve Apple Silicon'da aynı şekilde
    /// çalışıyor — bu M1 Air'de "ioreg -c AppleSmartBattery" ile ölçülüp
    /// IOHID sensörlerine karşı çapraz doğrulandı (30.2 °C / 28-29 °C,
    /// aynı aralık). "Temperature" anahtarı santi-Celsius cinsinden (örn.
    /// 3023 = 30.23 °C).
    private func pilSıcaklığınıOku() -> Double? {
        let servis = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")
        )
        guard servis != 0 else { return nil }
        defer { IOObjectRelease(servis) }

        var özelliklerRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(servis, &özelliklerRef, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let özellikler = özelliklerRef?.takeRetainedValue() as? [String: Any],
              let santiCelsius = özellikler["Temperature"] as? Int
        else { return nil }

        let derece = Double(santiCelsius) / 100
        return (-10.0 ... 130.0).contains(derece) ? derece : nil
    }

    private func bağlan() -> Bool {
        if bağlantı != 0 { return true }
        if denendi { return false }   // bir kere olmadıysa her saniye denemeyelim
        denendi = true

        let servis = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard servis != 0 else { return false }
        defer { IOObjectRelease(servis) }

        return IOServiceOpen(servis, mach_task_self_, 0, &bağlantı) == kIOReturnSuccess
    }

    private func çağır(_ girdi: inout SMCVeri, _ çıktı: inout SMCVeri) -> Bool {
        var çıktıBoyu = MemoryLayout<SMCVeri>.stride
        return IOConnectCallStructMethod(
            bağlantı, smcİşlevNo,
            &girdi, MemoryLayout<SMCVeri>.stride,
            &çıktı, &çıktıBoyu
        ) == kIOReturnSuccess
    }

    private func değerOku(_ anahtar: String) -> Double? {
        // 1. adım: anahtarın türünü ve kaç bayt olduğunu sor.
        var girdi = SMCVeri()
        var çıktı = SMCVeri()
        girdi.key = anahtarNumarası(anahtar)
        girdi.data8 = smcBilgiOku
        guard çağır(&girdi, &çıktı), çıktı.result == 0 else { return nil }

        let tür = çıktı.keyInfo.dataType
        let boyut = çıktı.keyInfo.dataSize

        // 2. adım: aynı bilgiyi geri verip değeri iste.
        girdi = SMCVeri()
        girdi.key = anahtarNumarası(anahtar)
        girdi.keyInfo = çıktı.keyInfo
        girdi.data8 = smcOku
        çıktı = SMCVeri()
        guard çağır(&girdi, &çıktı), çıktı.result == 0 else { return nil }

        return çöz(çıktı.bytes, tür: tür, boyut: boyut)
    }

    /// SMC iki farklı biçimde değer veriyor; hangisi olduğunu tür etiketi söylüyor.
    private func çöz(
        _ ham: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
        tür: UInt32, boyut: UInt32
    ) -> Double? {
        switch tür {
        case türSP78 where boyut >= 2:
            // sp78: işaretli sabit noktalı sayı. Üst bayt tam kısım, alt bayt
            // 1/256'lık kesir. 0x2A 0x40 -> 42.25 derece.
            return Double(Int8(bitPattern: ham.0)) + Double(ham.1) / 256

        case türFLT where boyut >= 4:
            // Baytları elle birleştiriyoruz. Diziye koyup load(as:) demek
            // hizalama garantisi olmadığı için tanımsız davranış; küçük
            // dizilerde çoğu zaman çalışır, bazen çöker.
            let ham32 = UInt32(ham.0)
                      | UInt32(ham.1) << 8
                      | UInt32(ham.2) << 16
                      | UInt32(ham.3) << 24
            return Double(Float(bitPattern: ham32))

        default:
            return nil   // tanımadığımız bir biçim; tahmin yürütmüyoruz
        }
    }
}
