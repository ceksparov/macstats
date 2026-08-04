import AppKit
import Combine
import SwiftUI
import MacStatsCore

// ============================================================================
// MENÜ BARINDAKİ GÖSTERGE
//
// Neden SwiftUI'ın hazır MenuBarExtra bileşenini değil de AppKit kullanıyoruz:
// menü barındaki yazının fontuna karşı tam denetim gerekiyor. Normal fontta
// rakamlar farklı genişlikte olduğu için "39°" ile "41°" farklı yer kaplıyor
// ve sayı her değiştiğinde yanındaki bütün menü bar ikonları kayıyor. Göz
// bunu titreme olarak görüyor ve sinir bozucu oluyor.
//
// Çözüm: her rakamın eşit genişlikte olduğu font (monospacedDigit). AppKit'te
// bu tek satır; SwiftUI tarafında menü bar etiketine bunu dayatmak güvenilir
// değil. Pencerenin İÇİ yine SwiftUI — orada böyle bir kısıt yok.
// ============================================================================

@MainActor
final class DurumÇubuğu: NSObject, NSPopoverDelegate {

    private let durumÖğesi = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pencere = NSPopover()
    private let depo = ÖlçümDeposu()
    private var abonelik: AnyCancellable?

    override init() {
        super.init()

        pencereyiKur()
        düğmeyiKur()

        // Her yeni ölçümde menü barındaki yazıyı tazele.
        abonelik = depo.$ölçüm.sink { [weak self] ölçüm in
            self?.yazıyıGüncelle(ölçüm)
        }
    }

    private func düğmeyiKur() {
        guard let düğme = durumÖğesi.button else { return }
        düğme.image = NSImage(systemSymbolName: "thermometer.medium",
                              accessibilityDescription: "İşlemci sıcaklığı")
        düğme.imagePosition = .imageLeading
        düğme.target = self
        düğme.action = #selector(düğmeyeTıklandı)
    }

    private func pencereyiKur() {
        pencere.behavior = .transient  // dışarı tıklayınca kapansın
        pencere.animates = false       // menü barında animasyon gecikmiş hissettiriyor
        pencere.delegate = self
        pencere.contentViewController = NSHostingController(
            rootView: PopupGörünümü(depo: depo)
        )
    }

    /// Menü barındaki yazıyı günceller.
    private func yazıyıGüncelle(_ ölçüm: Ölçüm?) {
        guard let düğme = durumÖğesi.button else { return }

        let derece = ölçüm?.sıcaklıklar?.işlemci
        let metin = " " + kısaSıcaklık(derece)

        düğme.attributedTitle = NSAttributedString(
            string: metin,
            attributes: [
                // Asıl mesele bu: eşit genişlikte rakamlar. Bu satır olmadan
                // sayı her değiştiğinde menü barı oynuyor.
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: renk(sıcaklıkSeviyesi(derece)),
            ]
        )
    }

    /// Sıcaklık seviyesine göre renk. Serin durumda özellikle nötr renk
    /// kullanıyoruz ki menü barındaki diğer ikonlarla uyumlu dursun ve
    /// gereksiz yere dikkat çekmesin — asıl uyarı rengi işe yarasın.
    private func renk(_ seviye: SıcaklıkSeviyesi) -> NSColor {
        switch seviye {
        case .serin, .bilinmiyor: return .labelColor
        case .ılık: return .systemOrange
        case .sıcak: return .systemRed
        }
    }

    @objc private func düğmeyeTıklandı() {
        if pencere.isShown {
            pencere.performClose(nil)
        } else {
            guard let düğme = durumÖğesi.button else { return }
            pencere.show(relativeTo: düğme.bounds, of: düğme, preferredEdge: .minY)
            // Pencere açıldığında öne gelmezse ilk tıklama yutuluyor.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSPopoverDelegate
    // Pencere açıkken daha sık ölçüyoruz, kapanınca geri seyreltiyoruz.

    func popoverDidShow(_ notification: Notification) {
        depo.pencereDurumuDeğişti(açık: true)
    }

    func popoverDidClose(_ notification: Notification) {
        depo.pencereDurumuDeğişti(açık: false)
    }
}
