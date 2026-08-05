import AppKit
import Combine
import SwiftUI
import MacStatsCore

// ============================================================================
// MENÜ BARINDAKİ GÖSTERGE
//
// NSPopover kullanıyoruz — NSMenu'den GERİ döndük. Sebebi: NSMenu'nün hiç
// animasyonu yok, OS anında çiziyor; NSPopover'ın kayarak açılıp kapanan
// varsayılan animasyonu var (.animates, varsayılan true — elle bir şey
// yapmıyoruz).
//
// Bunu daha önce bir kere denemiştik ve iki soruna takılmıştık:
//   1. Simgeye tekrar tıklayınca pencere kapanmıyordu. Sebep: AppKit
//      popover'ı önce kendi kapatıyor, hemen ardından bizim tıklama
//      işleyicimiz "kapalıymış, açayım" deyip anında yeniden açıyordu.
//   2. NSPopover'ın "transient" davranışı sadece AYNI UYGULAMANIN içindeki
//      tıklamalarda kapanıyor; başka bir uygulamaya tıklayınca hiç
//      tetiklenmiyordu, pencere ekranda takılı kalıyordu.
//
// İkisi de çözüldü: (1) performClose yerine koşulsuz close() — performClose
// bir "istek", hızlı art arda tıklamada yarıda kalabiliyordu; (2) uygulama
// dışındaki tıklamaları dinleyen kendi gözcümüz (aşağıda gözcüyüBaşlat/
// gözcüyüDurdur), OS'un transient davranışına güvenmek yerine.
//
// NSMenu'nün bir avantajını kaybettik: orada "Girişte başlat" ve "Çık" ayrı
// NSMenuItem'lardı. Popover'ın öyle bir liste kavramı yok — tek bir içerik
// görünümü. O yüzden ikisi de artık SwiftUI panelinin alt kısmında
// (bkz. PopupGorunumu.swift'teki altBar).
//
// Menü barındaki YAZI için hâlâ elle kurulmuş bir metin kullanıyoruz:
// rakamların eşit genişlikte olması gerekiyor, yoksa sayı her değiştiğinde
// yanındaki bütün menü bar simgeleri kayıyor ve göz bunu titreme olarak görüyor.
// ============================================================================

@MainActor
final class DurumÇubuğu: NSObject, NSPopoverDelegate {

    private let durumÖğesi = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pencere = NSPopover()
    private let depo = ÖlçümDeposu()
    private var abonelik: AnyCancellable?

    /// Pencere açıkken, uygulamanın DIŞINDAKİ tıklamaları dinleyen gözcü.
    private var dışTıklamaGözcüsü: Any?

    /// Renklendirilmemiş orijinal termometre simgesi. İki yerde lazım:
    /// henüz ölçüm yokken (varsayılan görünüm) ve her ölçümde yeni
    /// boyanmış bir kopya üretirken kaynak olarak.
    private var temelSimge: NSImage?

    override init() {
        super.init()
        düğmeyiKur()
        pencereyiKur()

        // Her yeni ölçümde menü barındaki yazıyı tazele.
        abonelik = depo.$ölçüm.sink { [weak self] ölçüm in
            self?.yazıyıGüncelle(ölçüm)
        }
    }

    private func düğmeyiKur() {
        guard let düğme = durumÖğesi.button else { return }
        // Şablon simge: rengini kendimiz boyuyoruz (bkz. boyanmışSimge).
        let simge = NSImage(systemSymbolName: "thermometer.medium",
                            accessibilityDescription: "İşlemci sıcaklığı")
        simge?.isTemplate = true
        temelSimge = simge
        düğme.image = simge
        düğme.imagePosition = .imageLeading
        düğme.target = self
        düğme.action = #selector(düğmeyeTıklandı)
    }

    private func pencereyiKur() {
        pencere.behavior = .transient
        // .animates elle ayarlanmıyor — varsayılan true, istediğimiz
        // kayarak açılma/kapanma efekti bu.
        pencere.delegate = self
        pencere.contentViewController = NSHostingController(
            rootView: PopupGörünümü(depo: depo)
        )
    }

    /// Menü barındaki yazıyı ve simgeyi günceller.
    private func yazıyıGüncelle(_ ölçüm: Ölçüm?) {
        guard let düğme = durumÖğesi.button else { return }

        let derece = ölçüm?.sıcaklıklar?.işlemci

        // contentTintColor DENENDİ VE ÇALIŞMADI (ekran görüntüsüyle piksel
        // piksel doğrulandı — status bar SF Symbol'leri bunu dikkate almıyor).
        // Onun yerine simgeyi kendimiz boyayıp yeni bir görüntü olarak veriyoruz.
        if let renk = simgeRengi(derece), let temelSimge {
            düğme.image = boyanmışSimge(temelSimge, renk: renk)
        } else {
            düğme.image = temelSimge
        }

        düğme.attributedTitle = NSAttributedString(
            string: " " + kısaSıcaklık(derece),
            attributes: [
                // Eşit genişlikte rakamlar. Bu satır olmadan sayı her
                // değiştiğinde menü barı oynuyor.
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    /// Termometre simgesinin rengi (bkz. IsiRengi.swift — 6 kademeli skala).
    private func simgeRengi(_ derece: Double?) -> NSColor? {
        guard let renk = ısıRengi(derece) else { return nil }
        return NSColor(srgbRed: renk.kırmızı, green: renk.yeşil, blue: renk.mavi, alpha: 1)
    }

    /// Şablon bir görüntüyü verilen renge boyar. `.sourceAtop` sadece şeklin
    /// İÇİNDE kalan piksellere boya sürüyor, şeffaf kısımlara dokunmuyor.
    private func boyanmışSimge(_ taban: NSImage, renk: NSColor) -> NSImage {
        let boyanmış = NSImage(size: taban.size)
        boyanmış.lockFocus()
        taban.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        renk.set()
        NSRect(origin: .zero, size: taban.size).fill(using: .sourceAtop)
        boyanmış.unlockFocus()
        return boyanmış
    }

    @objc private func düğmeyeTıklandı() {
        if pencere.isShown { kapat() } else { aç() }
    }

    private func aç() {
        guard let düğme = durumÖğesi.button, !pencere.isShown else { return }
        pencere.show(relativeTo: düğme.bounds, of: düğme, preferredEdge: .minY)
        // Pencerenin kendi penceresini "etkin" yapmak, uygulamanın tamamını
        // öne almadan (NSApp.activate olmadan) düğmelerin ilk tıklamada
        // çalışması için yeterli.
        pencere.contentViewController?.view.window?.makeKey()
        düğme.highlight(true)
        gözcüyüBaşlat()
    }

    private func kapat() {
        gözcüyüDurdur()
        durumÖğesi.button?.highlight(false)
        // performClose değil close: performClose bir kapatma "isteği" ve
        // reddedilebiliyor. Hızlı arka arkaya tıklamada istek yarıda kalıp
        // pencereyi ekranda bırakıyordu. close koşulsuz kapatır.
        pencere.close()
    }

    private func gözcüyüBaşlat() {
        gözcüyüDurdur()
        // Sadece fare tıklamalarını dinliyoruz — ek izin gerekmiyor.
        dışTıklamaGözcüsü = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.kapat() }
        }
    }

    private func gözcüyüDurdur() {
        if let dışTıklamaGözcüsü {
            NSEvent.removeMonitor(dışTıklamaGözcüsü)
        }
        dışTıklamaGözcüsü = nil
    }

    // MARK: - NSPopoverDelegate
    // Pencere açıkken daha sık ölçüyoruz, kapanınca geri seyreltiyoruz.

    func popoverDidShow(_ notification: Notification) {
        depo.pencereDurumuDeğişti(açık: true)
    }

    func popoverDidClose(_ notification: Notification) {
        // Pencere bizim kapat() dışında bir yoldan da kapanmış olabilir
        // (Esc, sistem). Gözcü ve vurgulama her hâlükârda temizlenmeli.
        gözcüyüDurdur()
        durumÖğesi.button?.highlight(false)
        depo.pencereDurumuDeğişti(açık: false)
    }
}
