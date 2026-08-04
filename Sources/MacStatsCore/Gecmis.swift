import Foundation

// ============================================================================
// SON 60 SANİYENİN GEÇMİŞİ
//
// Tek bir sayı "58 °C" der ama asıl merak edilen şeyi söylemez: tırmanıyor mu,
// oturdu mu? Bunun için son bir dakikayı saklıyoruz.
//
// Noktaları sayıya göre değil ZAMANA göre tutuyoruz. Sebebi: ölçüm sıklığı
// sabit değil — pencere kapalıyken 2 saniyede bir, açıkken 1 saniyede bir
// ölçüyoruz. Son N noktayı saklasaydık grafiğin kapsadığı süre pencereyi her
// açıp kapadığında değişirdi.
// ============================================================================

public struct GeçmişNoktası: Sendable {
    public let an: Date
    public let sıcaklık: Double?
    public let yük: Double?

    public init(an: Date, sıcaklık: Double?, yük: Double?) {
        self.an = an
        self.sıcaklık = sıcaklık
        self.yük = yük
    }
}

public struct Geçmiş: Sendable {

    /// Grafiğin kapsadığı süre.
    public static let pencereSaniye: TimeInterval = 60

    public private(set) var noktalar: [GeçmişNoktası] = []

    public init() {}

    public mutating func ekle(_ ölçüm: Ölçüm) {
        noktalar.append(GeçmişNoktası(
            an: ölçüm.an,
            sıcaklık: ölçüm.sıcaklıklar?.işlemci,
            yük: ölçüm.işlemci?.toplamYüzde
        ))
        pencereDışınıAt(şimdi: ölçüm.an)
    }

    /// Uykudan uyanınca çağrılır. Uykuda geçen süre boyunca ölçüm alınmadığı
    /// için elde kopuk bir geçmiş kalıyor; onu çizmek "bir dakika önce şuydu"
    /// izlenimi verir ki yanlış olur. Temiz sayfa açmak daha dürüst.
    public mutating func sıfırla() {
        noktalar.removeAll()
    }

    private mutating func pencereDışınıAt(şimdi: Date) {
        let sınır = şimdi.addingTimeInterval(-Self.pencereSaniye)
        noktalar.removeAll { $0.an < sınır }
    }
}


// MARK: - Grafik ölçeği

public struct GrafikÖlçeği: Sendable {
    public let alt: Double
    public let üst: Double

    public init(alt: Double, üst: Double) {
        self.alt = alt
        self.üst = üst
    }
}

/// Grafiğin dikey eksenini belirler.
///
/// Buradaki asıl mesele dürüstlük: eksen değerlere birebir uydurulursa
/// 1 derecelik bir oynama ekranda dağ gibi görünür ve insan boş yere
/// telaşlanır. O yüzden en az bir aralık dayatıyoruz (varsayılan 20 derece).
/// Küçük dalgalanmalar düz görünür, gerçek bir tırmanış grafiği doldurur.
public func grafikÖlçeği(_ değerler: [Double], enAzAralık: Double = 20) -> GrafikÖlçeği? {
    guard let enKüçük = değerler.min(), let enBüyük = değerler.max() else { return nil }

    let aralık = enBüyük - enKüçük
    if aralık >= enAzAralık {
        // Çizgi kenarlara yapışmasın diye biraz pay bırakıyoruz.
        let pay = aralık * 0.15
        return GrafikÖlçeği(alt: enKüçük - pay, üst: enBüyük + pay)
    }

    let merkez = (enKüçük + enBüyük) / 2
    return GrafikÖlçeği(alt: merkez - enAzAralık / 2, üst: merkez + enAzAralık / 2)
}
