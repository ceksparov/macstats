import AppKit
import Combine
import SwiftUI
import MacStatsCore

// ============================================================================
// MENÜ BARINDAKİ GÖSTERGE
//
// Neden NSMenu, neden NSPopover değil:
//
// Önce NSPopover kullanıyorduk ve iki sorun çıktı. Birincisi hız — popover
// gerçek bir pencere: uygulamanın öne gelmesi, pencerenin yaratılması ve
// içeriğin çizilmesi gerekiyor. NSMenu'yü ise işletim sisteminin menü sistemi
// çiziyor, uygulamanın öne gelmesine bile gerek yok. İkincisi de şuydu:
// menü barındaki simgeye tekrar tıklayınca pencere kapanmıyordu. Sebebi
// AppKit'in popover'ı önce kendi kapatması, hemen ardından bizim tıklama
// işleyicimizin "kapalıymış, açayım" deyip yeniden açmasıydı.
//
// NSMenu bu işlerin hepsini kendisi hallediyor: açma, kapama, tekrar tıklayınca
// kapanma, dışarı tıklayınca kapanma, Esc. Elle yazdığımız her şey (dış tıklama
// gözcüsü, koşulsuz kapatma, uygulamayı öne alma) gereksizleşti ve silindi.
//
// SwiftUI'dan vazgeçmedik: menünün ilk satırı, içine SwiftUI görünümü konmuş
// tek bir NSMenuItem. Yani düzen hâlâ SwiftUI, açılma hızı AppKit'in.
//
// Menü barındaki YAZI için hâlâ elle kurulmuş bir metin kullanıyoruz:
// rakamların eşit genişlikte olması gerekiyor, yoksa sayı her değiştiğinde
// yanındaki bütün menü bar simgeleri kayıyor ve göz bunu titreme olarak görüyor.
// ============================================================================

@MainActor
final class DurumÇubuğu: NSObject, NSMenuDelegate {

    private let durumÖğesi = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menü = NSMenu()
    private let depo = ÖlçümDeposu()
    private var abonelik: AnyCancellable?

    /// Menünün üst kısmındaki SwiftUI paneli. Depoyu kendisi izlediği için
    /// menü açıkken kendini yeniliyor.
    private var panel: NSHostingView<PopupGörünümü>?

    private var girişteBaşlatÖğesi: NSMenuItem?

    override init() {
        super.init()
        düğmeyiKur()
        menüyüKur()

        // Her yeni ölçümde menü barındaki yazıyı tazele.
        abonelik = depo.$ölçüm.sink { [weak self] ölçüm in
            self?.yazıyıGüncelle(ölçüm)
        }
    }

    private func düğmeyiKur() {
        guard let düğme = durumÖğesi.button else { return }
        // Şablon simge: rengini contentTintColor belirliyor. Şablon olmasaydı
        // simgenin kendi renkleri kullanılırdı ve boyayamazdık.
        let simge = NSImage(systemSymbolName: "thermometer.medium",
                            accessibilityDescription: "İşlemci sıcaklığı")
        simge?.isTemplate = true
        düğme.image = simge
        düğme.imagePosition = .imageLeading
    }

    private func menüyüKur() {
        menü.delegate = self

        // Üst kısım: bütün göstergeleri içeren tek bir SwiftUI görünümü.
        let panelÖğesi = NSMenuItem()
        let görünüm = NSHostingView(rootView: PopupGörünümü(depo: depo))
        // Menü içindeki görünümler kendi boylarını kendileri ayarlayamıyor;
        // ölçüyü SwiftUI'a sorup elle veriyoruz.
        görünüm.frame = NSRect(origin: .zero, size: görünüm.fittingSize)
        panelÖğesi.view = görünüm
        panel = görünüm
        menü.addItem(panelÖğesi)

        menü.addItem(.separator())

        // AYARLAR — ayrı bir pencereye gerek yok, menünün kendisi yeterli.
        let giriş = NSMenuItem(
            title: "Girişte başlat", action: #selector(girişteBaşlatDeğiştir), keyEquivalent: ""
        )
        giriş.target = self
        menü.addItem(giriş)
        girişteBaşlatÖğesi = giriş

        menü.addItem(.separator())

        menü.addItem(NSMenuItem(
            title: "Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))

        // Menüyü doğrudan durum öğesine bağlıyoruz: tıklama, tekrar tıklama,
        // dışarı tıklama ve Esc davranışlarını AppKit üstleniyor.
        durumÖğesi.menu = menü
    }

    /// Menü barındaki yazıyı günceller.
    private func yazıyıGüncelle(_ ölçüm: Ölçüm?) {
        guard let düğme = durumÖğesi.button else { return }

        let derece = ölçüm?.sıcaklıklar?.işlemci

        // Renk simgede, sayı nötr. Sayı da renkli olsaydı menü barında iki
        // renkli öğe yan yana dururdu ve rakamların okunması zorlaşırdı;
        // simge sinyali taşımaya yetiyor.
        düğme.contentTintColor = simgeRengi(derece)

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

    /// Termometre simgesinin rengi (bkz. IsiRengi.swift — kızılötesi ısı haritası).
    ///
    /// Menü barı, sistem açık temada olsa bile koyu olabiliyor (koyu duvar
    /// kâğıdında). O yüzden rengi sabit vermiyoruz: NSColor'a iki ton veriyoruz
    /// ve hangisinin kullanılacağına çizim anında menü barının kendi görünümü
    /// karar veriyor.
    private func simgeRengi(_ derece: Double?) -> NSColor? {
        guard derece != nil else { return nil }   // nil = menü barının kendi rengi
        return NSColor(name: nil) { görünüm in
            let koyu = görünüm.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            guard let renk = ısıRengi(derece, koyuZemin: koyu) else { return .labelColor }
            return NSColor(srgbRed: renk.kırmızı, green: renk.yeşil, blue: renk.mavi, alpha: 1)
        }
    }

    @objc private func girişteBaşlatDeğiştir() {
        GirişteBaşlat.ayarla(!GirişteBaşlat.açık)
        // Onay işaretini istediğimize değil GERÇEKLEŞENE göre koyuyoruz:
        // kayıt başarısız olabilir (örneğin .app paketi dışından çalışırken).
        girişteBaşlatÖğesi?.state = GirişteBaşlat.açık ? .on : .off
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        girişteBaşlatÖğesi?.state = GirişteBaşlat.açık ? .on : .off
        depo.pencereDurumuDeğişti(açık: true)

        // İçeriğin boyu değişmiş olabilir (grafik "veri toplanıyor" yazısından
        // gerçek çizime geçince). Menü açılmadan hemen önce ölçüyü tazeliyoruz.
        if let panel {
            panel.frame = NSRect(origin: .zero, size: panel.fittingSize)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        depo.pencereDurumuDeğişti(açık: false)
    }
}
