import SwiftUI
import MacStatsCore

// ============================================================================
// PANELDE ISI SKALASI
//
// Menü bar simgesi ve panelin içi (büyük sayı + grafik çizgisi) aynı
// fonksiyonu çağırıyor ki uygulama tek bir renk dili konuşsun. Bu dosya
// IsiRengi.swift'teki (MacStatsCore) skalayı SwiftUI'ın Color tipine çeviriyor.
// ============================================================================

/// Sıcaklığı panel rengine çevirir.
/// Okunamayan sıcaklık için `.secondary` döner — renkli bir sayı göstermek
/// "biliniyor" izlenimi verirdi.
func panelIsiRengi(_ derece: Double?) -> Color {
    guard let renk = ısıRengi(derece) else { return .secondary }
    return Color(red: renk.kırmızı, green: renk.yeşil, blue: renk.mavi)
}
