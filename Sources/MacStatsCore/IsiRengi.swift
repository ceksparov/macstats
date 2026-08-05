import Foundation

// ============================================================================
// SICAKLIK → RENK
//
// Menü bar simgesinin ve panelin (büyük sayı + grafik çizgisi) rengi buradan
// çıkıyor — ikisi de aynı fonksiyonu çağırıyor ki uygulama tek bir renk dili
// konuşsun.
//
// 6 kademeli, ayrık (sürekli geçişli değil) bir skala. Eşikler ve renkler bir
// M1 MacBook Air kullanıcısının kendi deneyimine göre belirlediği değerler:
// < 35 çok soğuk, 35-45 soğuk, 45-60 normal, 60-75 orta, 75-85 sıcak, 85+ çok
// sıcak. Önceki sürümde (kızılötesi ısı haritası, 30-85 arası sürekli
// geçişli) yeşil/turuncu/kırmızı kasıtlı olarak kullanılmamıştı; burada
// tam tersi — bu tablo bilerek geleneksel trafik ışığı mantığını kullanıyor.
// ============================================================================

/// Basit renk taşıyıcı. AppKit/SwiftUI'a bağlı olmasın diye kendi tipimiz —
/// böylece bu dosya test edilebiliyor.
public struct RGB: Sendable, Equatable {
    public let kırmızı: Double
    public let yeşil: Double
    public let mavi: Double

    public init(_ kırmızı: Double, _ yeşil: Double, _ mavi: Double) {
        self.kırmızı = kırmızı
        self.yeşil = yeşil
        self.mavi = mavi
    }

    /// 0xRRGGBB biçimindeki sayıdan.
    init(onaltılık: UInt32) {
        self.init(
            Double((onaltılık >> 16) & 0xFF) / 255,
            Double((onaltılık >> 8) & 0xFF) / 255,
            Double(onaltılık & 0xFF) / 255
        )
    }
}

private struct SıcaklıkKademesi {
    /// Bu kademenin üst sınırı (bu değere kadar, dahil değil). En üst
    /// kademede nil — üstte sınır yok.
    let üstSınır: Double?
    let renk: RGB
}

// Kademe sırası önemli: ısıRengi() ilk uyanı (derece < üstSınır olanı)
// döndürüyor, bu yüzden küçükten büyüğe sıralı olmalı.
private let ısıSkalası: [SıcaklıkKademesi] = [
    SıcaklıkKademesi(üstSınır: 35, renk: RGB(onaltılık: 0x2563EB)),   // 🧊 Çok soğuk
    SıcaklıkKademesi(üstSınır: 45, renk: RGB(onaltılık: 0x06B6D4)),   // ❄️ Soğuk
    SıcaklıkKademesi(üstSınır: 60, renk: RGB(onaltılık: 0x22C55E)),   // 🟢 Normal
    SıcaklıkKademesi(üstSınır: 75, renk: RGB(onaltılık: 0xEAB308)),   // 🟡 Orta
    SıcaklıkKademesi(üstSınır: 85, renk: RGB(onaltılık: 0xF97316)),   // 🟠 Sıcak
    SıcaklıkKademesi(üstSınır: nil, renk: RGB(onaltılık: 0xEF4444)),  // 🔴 Çok sıcak
]

/// Sıcaklığı simge/panel rengine çevirir.
/// Okunamayan sıcaklık için nil döner — o durumda renk yerine sistemin kendi
/// nötr rengi kullanılmalı, uydurma bir renk değil.
public func ısıRengi(_ derece: Double?) -> RGB? {
    guard let derece else { return nil }
    for kademe in ısıSkalası {
        guard let üst = kademe.üstSınır else { return kademe.renk }  // son kademe
        if derece < üst { return kademe.renk }
    }
    return ısıSkalası.last?.renk  // pratikte hiç buraya düşmez
}
