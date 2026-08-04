import XCTest
@testable import MacStatsCore

// Burada sadece SAF mantık test ediliyor: hesaplama ve biçimlendirme.
// Donanımdan okuyan kod test edilmiyor, çünkü sonucu makineye ve o anki
// yüke göre değişir — testin doğrulayabileceği sabit bir doğru cevabı yok.

final class BellekHesabıTests: XCTestCase {

    func testKullanılanBellekFormülü() {
        // 1000 sayfa uygulama belleği, 100'ü temizlenebilir (yani sayılmayacak),
        // 200 kilitli, 300 sıkıştırılmış -> (1000-100) + 200 + 300 = 1400 sayfa.
        let sayfalar = SayfaSayıları(
            dahili: 1000, temizlenebilir: 100, kilitli: 200, sıkıştırılmış: 300
        )
        XCTAssertEqual(kullanılanBellekBaytı(sayfalar, sayfaBoyutu: 16384), 1400 * 16384)
    }

    func testTemizlenebilirDahiliyiAşarsaSıfırlanır() {
        // Ölçümler tam olarak aynı ana ait olmadığı için bu teorik olarak
        // mümkün; çıkarma işlemi eksiye düşüp taşmamalı.
        let sayfalar = SayfaSayıları(
            dahili: 100, temizlenebilir: 500, kilitli: 50, sıkıştırılmış: 0
        )
        XCTAssertEqual(kullanılanBellekBaytı(sayfalar, sayfaBoyutu: 16384), 50 * 16384)
    }

}


final class SensörSeçimiTests: XCTestCase {

    /// Gerçek bir M1 Air taramasından alınmış örnek. Buradaki iki tuzağı
    /// koruma altına alıyoruz: "PMU tcal" sıcaklık değil kalibrasyon değeri
    /// (sabit 51.9) ve seçime karışmamalı.
    private let örnekOkumalar = [
        SensörOkuması(isim: "pACC MTR Temp Sensor2", derece: 41.2),
        SensörOkuması(isim: "pACC MTR Temp Sensor3", derece: 41.5),
        SensörOkuması(isim: "eACC MTR Temp Sensor0", derece: 36.9),
        SensörOkuması(isim: "GPU MTR Temp Sensor1", derece: 34.2),
        SensörOkuması(isim: "PMU tcal", derece: 51.9),
        SensörOkuması(isim: "gas gauge battery", derece: 28.8),
    ]

    func testÇekirdekSensörlerininEnYükseğiSeçilir() {
        XCTAssertEqual(enYüksek(örnekOkumalar, öneki: "pACC"), 41.5)
        XCTAssertEqual(enYüksek(örnekOkumalar, öneki: "eACC"), 36.9)
    }

    func testKalibrasyonSensörüİşlemciSıcaklığınaKarışmaz() {
        let sıcaklıklar = Sıcaklıklar(
            hızlıÇekirdekler: enYüksek(örnekOkumalar, öneki: "pACC"),
            verimliÇekirdekler: enYüksek(örnekOkumalar, öneki: "eACC"),
            grafik: nil, çipGövdesi: nil, pil: nil, depolama: nil,
            çekirdekler: nil, hamOkumalar: örnekOkumalar
        )
        // 51.9 (PMU tcal) değil, 41.5 (en sıcak çekirdek) beklenir.
        XCTAssertEqual(sıcaklıklar.işlemci, 41.5)
    }

    func testOlmayanGrupNilDöner() {
        // Sıfır değil nil: "0 derece" ile "bilmiyorum" aynı şey değil.
        XCTAssertNil(enYüksek(örnekOkumalar, öneki: "ANE"))
    }

    /// Sensör adlarının hangi bileşene ait sayıldığı. Bu eşleme başka Mac
    /// modellerinde uygulamanın çalışıp çalışmamasını belirliyor.
    func testSensörGruplaması() {
        XCTAssertEqual(sensörGrubu("pACC MTR Temp Sensor2"), .işlemciÇekirdeği)
        XCTAssertEqual(sensörGrubu("eACC MTR Temp Sensor0"), .işlemciÇekirdeği)
        XCTAssertEqual(sensörGrubu("GPU MTR Temp Sensor1"), .grafik)
        XCTAssertEqual(sensörGrubu("SOC MTR Temp Sensor0"), .çipGövdesi)
        XCTAssertEqual(sensörGrubu("PMU tdie1"), .çipGövdesi)
        XCTAssertEqual(sensörGrubu("gas gauge battery"), .pil)
        XCTAssertEqual(sensörGrubu("NAND CH0 temp"), .depolama)

        // Tanınmayanlar hiçbir yerde kullanılmamalı: kalibrasyon referansı ve
        // bağlı olmayan soketler.
        XCTAssertNil(sensörGrubu("PMU tcal"))
        XCTAssertNil(sensörGrubu("PMU tdev1"))
    }

    /// Çekirdek sensörü bulunamayan bir Mac'te işlemci sıcaklığı boş kalmamalı,
    /// çip gövdesine düşmeli.
    func testÇekirdekYoksaÇipGövdesineDüşer() {
        let sıcaklıklar = Sıcaklıklar(
            hızlıÇekirdekler: nil, verimliÇekirdekler: nil,
            grafik: nil, çipGövdesi: 47.2, pil: nil, depolama: nil,
            çekirdekler: nil, hamOkumalar: []
        )
        XCTAssertEqual(sıcaklıklar.işlemci, 47.2)
    }
}


final class BiçimlendirmeTests: XCTestCase {

    func testOkunamayanDeğerlerSayıGöstermez() {
        XCTAssertEqual(kısaSıcaklık(nil), bilinmiyorİşareti)
        XCTAssertEqual(uzunSıcaklık(nil), bilinmiyorİşareti)
        XCTAssertEqual(yüzde(nil), bilinmiyorİşareti)
        XCTAssertEqual(gigabayt(nil), bilinmiyorİşareti)
    }

    func testSıcaklıkBiçimleri() {
        XCTAssertEqual(kısaSıcaklık(41.5), "42°")
        XCTAssertEqual(kısaSıcaklık(41.4), "41°")
        XCTAssertEqual(uzunSıcaklık(41.46), "41.5 °C")
    }

    func testGigabaytÇevrimi() {
        XCTAssertEqual(gigabayt(1_073_741_824), "1.00 GB")
        XCTAssertEqual(gigabayt(8_589_934_592), "8.00 GB")
    }

    func testSıcaklıkSeviyesiEşikleri() {
        XCTAssertEqual(sıcaklıkSeviyesi(45), .serin)
        XCTAssertEqual(sıcaklıkSeviyesi(59.9), .serin)
        XCTAssertEqual(sıcaklıkSeviyesi(60), .ılık)
        XCTAssertEqual(sıcaklıkSeviyesi(79.9), .ılık)
        XCTAssertEqual(sıcaklıkSeviyesi(80), .sıcak)
        XCTAssertEqual(sıcaklıkSeviyesi(nil), .bilinmiyor)
    }

    /// Ölçülen gerçek değerler eşiklerin doğru tarafında kalmalı: bu makine
    /// boşta ~33 °C, 2.5 dakika tam yükte ~58 °C görüyor. İkisi de "serin"
    /// olmalı, yoksa renk uyarısı sürekli yanıp anlamını yitirir.
    func testÖlçülenGerçekDeğerlerSerinTarafta() {
        XCTAssertEqual(sıcaklıkSeviyesi(33.3), .serin)
        XCTAssertEqual(sıcaklıkSeviyesi(57.9), .serin)
    }
}


final class GeçmişTests: XCTestCase {

    private func ölçümÜret(an: Date, sıcaklık: Double) -> Ölçüm {
        Ölçüm(
            sıcaklıklar: Sıcaklıklar(
                hızlıÇekirdekler: sıcaklık, verimliÇekirdekler: nil,
                grafik: nil, çipGövdesi: nil, pil: nil, depolama: nil,
                çekirdekler: nil, hamOkumalar: []
            ),
            işlemci: nil, bellek: nil, pil: nil, termal: .normal, an: an
        )
    }

    func testPencereDışındakiNoktalarAtılır() {
        let başlangıç = Date()
        var geçmiş = Geçmiş()

        // 0., 30. ve 90. saniyeler. İlki 60 saniyelik pencerenin dışında kalmalı.
        geçmiş.ekle(ölçümÜret(an: başlangıç, sıcaklık: 40))
        geçmiş.ekle(ölçümÜret(an: başlangıç.addingTimeInterval(30), sıcaklık: 50))
        geçmiş.ekle(ölçümÜret(an: başlangıç.addingTimeInterval(90), sıcaklık: 60))

        XCTAssertEqual(geçmiş.noktalar.count, 2)
        XCTAssertEqual(geçmiş.noktalar.first?.sıcaklık, 50)
    }

    func testUykuSonrasıSıfırlanır() {
        var geçmiş = Geçmiş()
        geçmiş.ekle(ölçümÜret(an: Date(), sıcaklık: 40))
        XCTAssertFalse(geçmiş.noktalar.isEmpty)

        geçmiş.sıfırla()
        XCTAssertTrue(geçmiş.noktalar.isEmpty)
    }
}


final class GrafikÖlçeğiTests: XCTestCase {

    func testKüçükDalgalanmaBüyütülmez() {
        // 1 derecelik oynama, eksene birebir uydurulsaydı dağ gibi görünürdü.
        // En az 20 derecelik aralık dayatıldığı için düz görünmeli.
        let ölçek = grafikÖlçeği([40.0, 41.0])
        // 40.5 merkezli, 20 derece genişliğinde bir pencere beklenir.
        XCTAssertEqual(ölçek?.alt ?? 0, 30.5, accuracy: 0.001)
        XCTAssertEqual(ölçek?.üst ?? 0, 50.5, accuracy: 0.001)
    }

    func testGerçekTırmanışGrafiğiDoldurur() {
        // Ölçtüğümüz yük denemesi: 45 -> 58 derece. Aralık 20'nin altında
        // olduğu için yine en az aralık uygulanır.
        let ölçek = grafikÖlçeği([45.3, 49.7, 51.3, 54.9, 57.9])
        XCTAssertEqual((ölçek?.üst ?? 0) - (ölçek?.alt ?? 0), 20, accuracy: 0.001)

        // Geniş bir aralıkta ise değerlere uyup biraz pay bırakır.
        let geniş = grafikÖlçeği([30.0, 90.0])
        XCTAssertEqual(geniş?.alt ?? 0, 21, accuracy: 0.001)
        XCTAssertEqual(geniş?.üst ?? 0, 99, accuracy: 0.001)
    }

    func testBoşListeÖlçekVermez() {
        XCTAssertNil(grafikÖlçeği([]))
    }
}
