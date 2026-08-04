import Foundation
import ServiceManagement

// ============================================================================
// GİRİŞTE BAŞLAT
//
// Apple'ın SMAppService'i ile. Eski yöntemlerin (login item ekleme, launchd
// plist yazma) aksine kullanıcıdan izin istemiyor ve Sistem Ayarları'nın
// "Giriş Öğeleri" listesinde düzgün görünüyor.
//
// ÖNEMLİ: Sadece gerçek bir .app paketi içinden çalışır. "swift run" ile
// çalıştırdığında kayıt başarısız olur — bu bir hata değil, beklenen durum.
// Denemek için ./build-app.sh kullan.
// ============================================================================

enum GirişteBaşlat {

    static var açık: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Durumu değiştirir. Başarısız olursa false döner ki arayüz onay
    /// işaretini yanlış yere koymasın.
    @discardableResult
    static func ayarla(_ istenen: Bool) -> Bool {
        do {
            if istenen {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            // Tipik sebep: .app paketi dışından çalıştırılmış olması.
            NSLog("macstats: girişte başlat ayarlanamadı — \(error.localizedDescription)")
            return false
        }
    }
}
