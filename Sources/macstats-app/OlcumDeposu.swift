import AppKit
import Combine
import Foundation
import MacStatsCore

// ============================================================================
// ÖLÇÜM DEPOSU
//
// Belirli aralıklarla ölçüm alır ve sonucu arayüze duyurur. Arayüzün tek
// veri kaynağı burası; ekrandaki hiçbir parça donanıma doğrudan dokunmuyor.
// ============================================================================

@MainActor
public final class ÖlçümDeposu: ObservableObject {

    /// En son ölçüm. Arayüz bunu izliyor, her değiştiğinde kendini yeniliyor.
    @Published public private(set) var ölçüm: Ölçüm?

    /// Son 60 saniyenin ölçümleri — popup'taki mini grafik için.
    @Published public private(set) var geçmiş = Geçmiş()

    /// Ölçüm işi bu kuyrukta yapılıyor, ana iş parçacığında değil.
    ///
    /// Sebebi: sensör okuması donanımla konuştuğu için birkaç milisaniye
    /// sürüyor ve bu süre ana iş parçacığını kilitliyordu. Menü açıkken
    /// saniyede bir olduğu için tam da kullanıcının menüyle uğraştığı anda
    /// takılmaya yol açıyordu.
    ///
    /// Sıralı bir kuyruk seçtik: sensör bağlantısı tek bir iş parçacığından
    /// kullanılmalı, paralel kuyruk olsa aynı anda iki okuma çakışabilirdi.
    private let ölçümKuyruğu = DispatchQueue(label: "macstats.olcum", qos: .utility)

    /// Sadece ölçümKuyruğu üzerinden dokunuluyor.
    nonisolated(unsafe) private let toplayıcı = ÖlçümToplayıcı()

    private var zamanlayıcı: Timer?

    /// Pencere kapalıyken seyrek, açıkken sık ölçüyoruz.
    ///
    /// Neden 2 saniye: sensör donanımının kendisi zaten 3-4 saniyede bir
    /// yenileniyor, daha sık okumak aynı sayıyı tekrar okumaktan ibaret.
    /// Pencere açıkken 1 saniye, çünkü orada işlemci çubukları var ve onlar
    /// gerçekten hızlı değişiyor.
    private let kapalıykenAralık: TimeInterval = 2.0
    private let açıkkenAralık: TimeInterval = 1.0

    private var pencereAçık = false

    public init() {
        zamanlayıcıyıKur()

        // Mac uykudan uyandığında sensör bağlantısı ölmüş, işlemci sayaçları da
        // anlamsız bir sıçrama yapmış olabilir. Bunu fark etmek zordur — ekranda
        // saatlerce eski değer durur ve hata gibi görünmez. O yüzden baştan
        // dinliyoruz.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.uykudanUyandı()
            }
        }
    }

    /// Pencere açılıp kapandıkça ölçüm sıklığını değiştirir.
    public func pencereDurumuDeğişti(açık: Bool) {
        guard açık != pencereAçık else { return }
        pencereAçık = açık
        zamanlayıcıyıKur()
        if açık { ölç() }  // Açılır açılmaz taze veri göster, bir saniye bekletme.
    }

    private func zamanlayıcıyıKur() {
        zamanlayıcı?.invalidate()
        let aralık = pencereAçık ? açıkkenAralık : kapalıykenAralık
        let yeni = Timer(timeInterval: aralık, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ölç()
            }
        }
        // .common modu olmadan, menüler açıkken zamanlayıcı duruyor — kullanıcı
        // menü barına tıkladığı anda sayılar donmuş görünüyordu.
        RunLoop.main.add(yeni, forMode: .common)
        zamanlayıcı = yeni
        ölç()
    }

    private func ölç() {
        ölçümKuyruğu.async { [weak self] in
            guard let self else { return }
            let yeni = self.toplayıcı.ölç()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.ölçüm = yeni
                    self.geçmiş.ekle(yeni)
                }
            }
        }
    }

    private func uykudanUyandı() {
        // Uykuda ölçüm alınmadı; eldeki geçmişi çizmek "bir dakika önce şuydu"
        // izlenimi verirdi ki doğru değil.
        geçmiş.sıfırla()
        // Toplayıcıya da kendi kuyruğundan dokunuyoruz — başka bir iş
        // parçacığından çağırmak sensör bağlantısını iki yerden kullanmak olurdu.
        ölçümKuyruğu.async { [weak self] in
            self?.toplayıcı.uykudanUyandı()
        }
        ölç()
    }
}
