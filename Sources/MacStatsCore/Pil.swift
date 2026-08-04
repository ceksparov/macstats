import Foundation
import IOKit

// ============================================================================
// PİL
//
// Sıcaklığın aksine burada belgelenmemiş bir şey yok: pil bilgisi IORegistry
// denen, sistemin herkese açık aygıt kayıt defterinde duruyor. Terminalde
// "ioreg -c AppleSmartBattery" yazınca görülen bilgilerin aynısı.
//
// 2020 model bir makinede en çok merak edilen şey bu: pil kaç devir yapmış ve
// ne kadarı kalmış.
// ============================================================================

public struct PilDurumu: Sendable {
    /// Kaç tam şarj döngüsü yapılmış. Apple M1 Air için 1000 devir sınır kabul
    /// ediyor; ondan sonra pil "servis önerilir" durumuna geçiyor.
    public let döngü: Int?

    /// Pilin bugünkü kapasitesinin fabrika kapasitesine oranı (%).
    /// Sistem Ayarları'ndaki "Pil Sağlığı" ile aynı hesap.
    public let sağlıkYüzdesi: Double?

    /// Şu anki şarj seviyesi (%).
    public let şarjYüzdesi: Double?

    /// Fişte mi.
    public let şarjOluyor: Bool?
}


public struct PilOkuyucu {

    public init() {}

    public func oku() -> PilDurumu? {
        // Bu Mac'te pil var mı? (Mac mini/Studio'da yok — nil dönmek doğru.)
        let servis = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")
        )
        guard servis != 0 else { return nil }
        defer { IOObjectRelease(servis) }

        var özelliklerRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(servis, &özelliklerRef, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let özellikler = özelliklerRef?.takeRetainedValue() as? [String: Any]
        else { return nil }

        let döngü = özellikler["CycleCount"] as? Int

        // Sağlık = bugünkü kapasite / fabrika kapasitesi.
        //
        // "MaxCapacity" anahtarını KULLANMIYORUZ: adı öyle olmasına rağmen
        // yeni macOS sürümlerinde sabit 100 dönüyor (bu makinede de öyle),
        // yani sağlık değil şarj yüzdesi anlamına geliyor. Gerçek kapasite
        // NominalChargeCapacity'de duruyor.
        let fabrika = özellikler["DesignCapacity"] as? Int
        let bugünkü = (özellikler["NominalChargeCapacity"] as? Int)
                   ?? (özellikler["AppleRawMaxCapacity"] as? Int)

        var sağlık: Double?
        if let fabrika, let bugünkü, fabrika > 0 {
            sağlık = Double(bugünkü) / Double(fabrika) * 100
        }

        // Şarj seviyesi: yüzde olarak doğrudan duruyor.
        let şarj = (özellikler["CurrentCapacity"] as? Int).map(Double.init)

        return PilDurumu(
            döngü: döngü,
            sağlıkYüzdesi: sağlık,
            şarjYüzdesi: şarj,
            şarjOluyor: özellikler["IsCharging"] as? Bool
        )
    }
}
