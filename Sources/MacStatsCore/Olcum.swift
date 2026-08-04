import Foundation

// ============================================================================
// ÖLÇÜM TOPLAMA VE BİÇİMLENDİRME
//
// Buradaki kod donanıma hiç dokunmaz; eldeki sayıları bir araya getirir ve
// ekrana yazılacak metne çevirir. Saf olduğu için tamamı test edilebilir.
// ============================================================================


/// Apple'ın kendi termal değerlendirmesi.
///
/// Bu RESMÎ, belgelenmiş bir API. Sıcaklık sensörleri bir gün bozulsa bile
/// bu çalışmaya devam eder — o yüzden yedek/tamamlayıcı gösterge olarak
/// bilerek yanına koyuyoruz.
public enum TermalDurum: String, Sendable {
    case normal   = "normal"
    case orta     = "orta"
    case ciddi    = "ciddi"
    case kritik   = "kritik"
    case bilinmiyor = "bilinmiyor"

    public static func sistemden() -> TermalDurum {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return .normal
        case .fair:     return .orta
        case .serious:  return .ciddi
        case .critical: return .kritik
        @unknown default: return .bilinmiyor
        }
    }
}


/// Tek bir andaki bütün ölçümler.
/// Alanların hepsi nil olabilir: bir ölçüm alınamadığında sıfır göstermek
/// yalan olur, "bilinmiyor" göstermek dürüst.
public struct Ölçüm: Sendable {
    public let sıcaklıklar: Sıcaklıklar?
    public let işlemci: İşlemciYükü?
    public let bellek: BellekDurumu?
    public let termal: TermalDurum
    public let an: Date
}


/// Bütün okuyucuları bir arada tutan üst katman.
/// Uygulama tarafı sadece bunu tanıyacak; hangi verinin nereden geldiğiyle
/// ilgilenmesine gerek yok.
public final class ÖlçümToplayıcı {
    private let sıcaklıkOkuyucu = SıcaklıkOkuyucu()
    private let işlemciOkuyucu = İşlemciOkuyucu()
    private let bellekOkuyucu = BellekOkuyucu()

    public init() {}

    public func ölç() -> Ölçüm {
        Ölçüm(
            sıcaklıklar: sıcaklıkOkuyucu.oku(),
            işlemci: işlemciOkuyucu.oku(),
            bellek: bellekOkuyucu.oku(),
            termal: TermalDurum.sistemden(),
            an: Date()
        )
    }

    /// Mac uykudan uyandığında çağrılmalı. Uyku sırasında sensör bağlantısı
    /// ölmüş, işlemci sayaçları da anlamsız bir sıçrama yapmış olabilir.
    public func uykudanUyandı() {
        sıcaklıkOkuyucu.bağlantıyıYenile()
        işlemciOkuyucu.referansıSıfırla()
    }
}


// MARK: - Biçimlendirme
//
// Okunamayan her değer için "—" gösteriyoruz. Bu bilinçli bir karar:
// yanlış bir sıcaklık, sıcaklık olmamasından beterdir.

public let bilinmiyorİşareti = "—"

/// Sıcaklığı menü bar için kısa biçimde yazar: "42°"
public func kısaSıcaklık(_ derece: Double?) -> String {
    guard let derece else { return bilinmiyorİşareti }
    return "\(Int(derece.rounded()))°"
}

/// Sıcaklığı popup için ondalıklı yazar: "42.3 °C"
public func uzunSıcaklık(_ derece: Double?) -> String {
    guard let derece else { return bilinmiyorİşareti }
    return String(format: "%.1f °C", derece)
}

/// Yüzdeyi yazar: "37%"
public func yüzde(_ değer: Double?) -> String {
    guard let değer else { return bilinmiyorİşareti }
    return "\(Int(değer.rounded()))%"
}

/// Bayt sayısını insan ölçeğine çevirir: "6.2 GB"
/// 1 GB = 1024³ alıyoruz, Activity Monitor'ün aksine — Apple 1000³ kullanıyor.
/// Bunu bilerek seçtik ki bellek sayfalarıyla yaptığımız hesap kendi içinde
/// tutarlı kalsın; aradaki fark %7 civarı ve her iki yerde de aynı yönde.
public func gigabayt(_ bayt: UInt64?) -> String {
    guard let bayt else { return bilinmiyorİşareti }
    return String(format: "%.2f GB", Double(bayt) / 1_073_741_824)
}

/// Sıcaklığı üç kabaca seviyeye ayırır. Menü barda renk seçmek için.
///
/// Eşikler bu makinede ölçülerek belirlendi. Önce 70/90 denenmişti, ama
/// 8 çekirdek 2.5 dakika tam yükte çalıştırıldığında sıcaklık ancak 58 °C'ye
/// çıktı — yani o eşiklerle renkler hiç görünmeyecek, ölü bir özellik olacaktı.
/// 60/80 ile turuncu "makine gerçekten çalışıyor", kırmızı "buna bir bak"
/// anlamına geliyor.
public enum SıcaklıkSeviyesi: Sendable {
    case serin    // < 60
    case ılık     // 60–79
    case sıcak    // >= 80
    case bilinmiyor
}

public func sıcaklıkSeviyesi(_ derece: Double?) -> SıcaklıkSeviyesi {
    guard let derece else { return .bilinmiyor }
    switch derece {
    case ..<60: return .serin
    case ..<80: return .ılık
    default:    return .sıcak
    }
}
