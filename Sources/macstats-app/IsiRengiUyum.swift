import SwiftUI
import MacStatsCore

// ============================================================================
// PANELDE ISI SKALASI
//
// Menü bar simgesi kızılötesi ısı haritasını (mor -> fuşya -> kehribar)
// kullanıyor, ama panelin içindeki büyük sıcaklık sayısı ve grafik çizgisi
// eski turuncu/kırmızı ikiliyi kullanmaya devam ediyordu — unutulmuştu.
// Aynı uygulamanın iki yerinde iki farklı renk dili konuşması tutarsız
// duruyordu. Bu dosya IsiRengi.swift'teki (MacStatsCore) skalayı SwiftUI'ın
// Color tipine çeviriyor ki panel de aynı dili konuşsun.
// ============================================================================

/// Sıcaklığı geçerli aydınlık/karanlık görünüme göre panel rengine çevirir.
/// Okunamayan sıcaklık için `.secondary` döner — renkli bir sayı göstermek
/// "biliniyor" izlenimi verirdi.
func panelIsiRengi(_ derece: Double?, karanlık: Bool) -> Color {
    guard let renk = ısıRengi(derece, koyuZemin: karanlık) else { return .secondary }
    return Color(red: renk.kırmızı, green: renk.yeşil, blue: renk.mavi)
}
