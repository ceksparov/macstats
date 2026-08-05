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

    /// Renklendirilmemiş orijinal termometre simgesi. İki yerde lazım:
    /// henüz ölçüm yokken (varsayılan görünüm) ve her ölçümde yeni
    /// boyanmış bir kopya üretirken kaynak olarak.
    private var temelSimge: NSImage?

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
        temelSimge = simge
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
        //
        // contentTintColor DENENDİ VE ÇALIŞMADI: ekran görüntüsüyle piksel
        // piksel doğrulandı, hem statik hem dinamik NSColor ile simge hep
        // varsayılan siyah-beyaz kaldı (R=G=B). Status bar'daki SF Symbol
        // görüntüleri bu özelliği bu ortamda hiç dikkate almıyor. Onun yerine
        // simgeyi kendimiz boyayıp yeni bir görüntü olarak veriyoruz —
        // sistemin otomatik tonlamasına bağlı değil, garantili çalışıyor.
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

    /// Şablon bir görüntüyü verilen renge boyar.
    ///
    /// contentTintColor'a güvenmek yerine bunu tercih ediyoruz: alfa
    /// kanalını (şeklin kendisini) koruyup üstüne düz renk dolduruyoruz —
    /// `.sourceAtop` sadece şeklin İÇİNDE kalan piksellere boya sürüyor,
    /// şeffaf kısımlara dokunmuyor. Sonuç, sistemin otomatik tonlama
    /// mekanizmasından bağımsız, garantili şekilde boyanmış bir görüntü.
    private func boyanmışSimge(_ taban: NSImage, renk: NSColor) -> NSImage {
        let boyanmış = NSImage(size: taban.size)
        boyanmış.lockFocus()
        taban.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        renk.set()
        NSRect(origin: .zero, size: taban.size).fill(using: .sourceAtop)
        boyanmış.unlockFocus()
        return boyanmış
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
