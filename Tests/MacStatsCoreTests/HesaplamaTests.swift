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

    func testBaskıSeviyeleri() {
        XCTAssertEqual(BellekBaskısı.hamDeğerden(1), .normal)
        XCTAssertEqual(BellekBaskısı.hamDeğerden(2), .uyarı)
        XCTAssertEqual(BellekBaskısı.hamDeğerden(4), .kritik)
        // Beklenmedik bir değer gelirse tahmin yürütmüyoruz.
        XCTAssertEqual(BellekBaskısı.hamDeğerden(99), .bilinmiyor)
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
            hamOkumalar: örnekOkumalar
        )
        // 51.9 (PMU tcal) değil, 41.5 (en sıcak çekirdek) beklenir.
        XCTAssertEqual(sıcaklıklar.işlemci, 41.5)
    }

    func testOlmayanGrupNilDöner() {
        // Sıfır değil nil: "0 derece" ile "bilmiyorum" aynı şey değil.
        XCTAssertNil(enYüksek(örnekOkumalar, öneki: "ANE"))
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
        XCTAssertEqual(sıcaklıkSeviyesi(69.9), .serin)
        XCTAssertEqual(sıcaklıkSeviyesi(70), .ılık)
        XCTAssertEqual(sıcaklıkSeviyesi(89.9), .ılık)
        XCTAssertEqual(sıcaklıkSeviyesi(90), .sıcak)
        XCTAssertEqual(sıcaklıkSeviyesi(nil), .bilinmiyor)
    }
}
