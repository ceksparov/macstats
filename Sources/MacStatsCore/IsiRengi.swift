import Foundation

// ============================================================================
// SICAKLIK → RENK
//
// Menü barındaki termometre simgesinin rengi buradan çıkıyor.
//
// Neden trafik ışığı (yeşil/turuncu/kırmızı) değil:
//   - Yeşil "her şey yolunda", kırmızı "sorun var" demek. Ama bir işlemcinin
//     ısınması sorun değil, işini yapması demek. Yanlış duygu veriyordu.
//   - Menü barında zaten pil, wifi gibi şeyler o renkleri kullanıyor.
//
// Onun yerine kızılötesi kameraların ısı haritası: soğukta lacivert-mor,
// ısındıkça mor, fuşya, en sıcakta kehribar. Bu skalanın iki iyi yanı var:
//   - Sıcaklık arttıkça renk sadece değişmiyor, AÇILIYOR da. Yani renkleri
//     ayırt edemeyen biri bile parlaklıktan durumu okuyabiliyor.
//   - Sıcaklık için zaten tanıdık bir dil.
//
// Renkler ara değerlerle geçişli: 42 °C ile 43 °C arasında ani sıçrama yok.
// Menü barının açık ya da koyu olmasına göre iki ayrı ton var; tek bir renk
// ikisinde birden okunaklı olmuyor.
// ============================================================================

/// Basit renk taşıyıcı. AppKit'e bağlı olmasın diye kendi tipimiz —
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

private struct RenkDurağı {
    let derece: Double
    let açıkZemin: RGB   // açık menü barında kullanılacak ton
    let koyuZemin: RGB   // koyu menü barında kullanılacak ton
}

// Duraklar arasında hem kırmızı sürekli artıyor hem mavi sürekli azalıyor —
// yani renk sıralaması tek yönlü. Bu testle korunuyor; bozulursa skala
// "daha sıcak" hissini vermeyi bırakır.
//
// Aralık 30–85 °C. Alt uç bu makinenin boştaki sıcaklığı, üst uç ise
// gerçekten dikkat edilmesi gereken yer. Dışına taşanlar uçlara sabitleniyor.
private let ısıSkalası: [RenkDurağı] = [
    RenkDurağı(derece: 30,
               açıkZemin: RGB(onaltılık: 0x4A4AD8),   // lacivert-mor
               koyuZemin: RGB(onaltılık: 0x9A9AF5)),
    RenkDurağı(derece: 50,
               açıkZemin: RGB(onaltılık: 0x8A3FC8),   // mor
               koyuZemin: RGB(onaltılık: 0xB98BEE)),
    RenkDurağı(derece: 70,
               açıkZemin: RGB(onaltılık: 0xC63A8C),   // fuşya
               koyuZemin: RGB(onaltılık: 0xF07CC0)),
    RenkDurağı(derece: 85,
               açıkZemin: RGB(onaltılık: 0xD1701A),   // kehribar
               koyuZemin: RGB(onaltılık: 0xF7A845)),
]

/// Sıcaklığı simge rengine çevirir.
/// Okunamayan sıcaklık için nil döner — o durumda simge menü barının kendi
/// rengini kullanmalı, uydurma bir renk değil.
public func ısıRengi(_ derece: Double?, koyuZemin: Bool) -> RGB? {
    guard let derece else { return nil }

    let ilk = ısıSkalası[0]
    let son = ısıSkalası[ısıSkalası.count - 1]
    if derece <= ilk.derece { return koyuZemin ? ilk.koyuZemin : ilk.açıkZemin }
    if derece >= son.derece { return koyuZemin ? son.koyuZemin : son.açıkZemin }

    for i in 0 ..< (ısıSkalası.count - 1) {
        let alt = ısıSkalası[i]
        let üst = ısıSkalası[i + 1]
        guard derece >= alt.derece, derece <= üst.derece else { continue }

        let oran = (derece - alt.derece) / (üst.derece - alt.derece)
        let a = koyuZemin ? alt.koyuZemin : alt.açıkZemin
        let b = koyuZemin ? üst.koyuZemin : üst.açıkZemin
        return RGB(
            a.kırmızı + (b.kırmızı - a.kırmızı) * oran,
            a.yeşil + (b.yeşil - a.yeşil) * oran,
            a.mavi + (b.mavi - a.mavi) * oran
        )
    }
    return nil
}
