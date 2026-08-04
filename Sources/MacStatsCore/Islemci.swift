import Foundation

// ============================================================================
// İŞLEMCİ KULLANIMI
//
// Buradaki her şey Apple'ın resmî, belgelenmiş arayüzüyle okunuyor (mach).
// Sıcaklığın aksine hiçbir arka kapı yok, macOS güncellemesinde bozulmaz.
//
// Önemli ayrıntı: macOS sana "şu anda %35 meşgulüm" demez. Sana açılıştan
// beri geçen toplam süreleri verir — "şu kadar süre iş yaptım, şu kadar süre
// boş durdum". Yüzdeyi bulmak için iki ölçüm arasındaki FARKA bakmak gerekir.
// Bu yüzden ilk ölçüm her zaman sonuçsuzdur: karşılaştıracak bir öncesi yok.
// ============================================================================


/// Bir çekirdeğin, açılıştan beri her durumda geçirdiği süre.
/// Birim "tik" — sabit uzunlukta küçük zaman dilimleri.
private struct ÇekirdekTikleri {
    var kullanıcı: Double   // normal uygulamalar
    var sistem: Double      // işletim sisteminin kendi işi
    var boşta: Double       // hiçbir şey yapmadan geçen süre
    var düşükÖncelik: Double  // arka plana atılmış işler (nice)

    var toplam: Double { kullanıcı + sistem + boşta + düşükÖncelik }
    var meşgul: Double { kullanıcı + sistem + düşükÖncelik }
}


/// Bir ölçüm anındaki işlemci kullanımı.
public struct İşlemciYükü: Sendable {
    /// 0–100 arası. Bütün çekirdeklerin ortalaması.
    ///
    /// Activity Monitor bunu farklı gösterir: orada 8 çekirdek tam çalışırken
    /// %800 yazar. Biz %100'ü "makine tamamen dolu" olarak tanımladık, çünkü
    /// menü barda tek bir sayıya bakan insan için okuması bu daha kolay.
    public let toplamYüzde: Double

    /// Her çekirdek için ayrı yüzde. Popup'ta çubuk göstermek için.
    /// M1'de 8 tane: ilk 4'ü verimlilik, son 4'ü performans çekirdeği.
    public let çekirdekYüzdeleri: [Double]

    /// Yükün ne kadarı senin uygulamalarından, ne kadarı işletim sisteminden.
    public let kullanıcıYüzde: Double
    public let sistemYüzde: Double
}


public final class İşlemciOkuyucu {

    /// Bir önceki ölçümün tikleri. Yüzde bunun farkından çıkıyor.
    private var öncekiTikler: [ÇekirdekTikleri]?

    public init() {}

    /// Uykudan uyanma sonrası çağrılmalı. Uyku boyunca geçen süre farkı
    /// anlamsız bir yüzde üretir; elimizdeki referansı atıp sıfırdan başlıyoruz.
    public func referansıSıfırla() {
        öncekiTikler = nil
    }

    /// İşlemci kullanımını okur.
    /// İLK ÇAĞRIDA nil DÖNER — karşılaştırılacak önceki ölçüm olmadığı için.
    /// Bu bir hata değil, yöntemin doğası.
    public func oku() -> İşlemciYükü? {
        guard let şimdiki = tikleriOku() else { return nil }
        defer { öncekiTikler = şimdiki }

        guard let önceki = öncekiTikler, önceki.count == şimdiki.count else {
            return nil
        }

        var çekirdekYüzdeleri: [Double] = []
        var toplamMeşgulFarkı = 0.0
        var toplamKullanıcıFarkı = 0.0
        var toplamSistemFarkı = 0.0
        var toplamFark = 0.0

        for (yeni, eski) in zip(şimdiki, önceki) {
            let farkToplam = yeni.toplam - eski.toplam
            let farkMeşgul = yeni.meşgul - eski.meşgul

            // Sayaçlar taşıp başa dönebilir; o durumda fark negatif çıkar ve
            // saçma bir yüzde üretir. Böyle bir ölçümü %0 sayıp geçiyoruz.
            guard farkToplam > 0, farkMeşgul >= 0 else {
                çekirdekYüzdeleri.append(0)
                continue
            }

            çekirdekYüzdeleri.append(farkMeşgul / farkToplam * 100)
            toplamMeşgulFarkı += farkMeşgul
            toplamKullanıcıFarkı += yeni.kullanıcı - eski.kullanıcı
            toplamSistemFarkı += yeni.sistem - eski.sistem
            toplamFark += farkToplam
        }

        guard toplamFark > 0 else { return nil }
        return İşlemciYükü(
            toplamYüzde: toplamMeşgulFarkı / toplamFark * 100,
            çekirdekYüzdeleri: çekirdekYüzdeleri,
            kullanıcıYüzde: toplamKullanıcıFarkı / toplamFark * 100,
            sistemYüzde: toplamSistemFarkı / toplamFark * 100
        )
    }

    /// Çekirdek başına ham tik sayaçlarını çekirdekten okur.
    private func tikleriOku() -> [ÇekirdekTikleri]? {
        var çekirdekSayısı: natural_t = 0
        var tablo: processor_info_array_t?
        var tabloUzunluğu: mach_msg_type_number_t = 0

        let sonuç = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
            &çekirdekSayısı, &tablo, &tabloUzunluğu
        )
        guard sonuç == KERN_SUCCESS, let tablo else { return nil }

        // Bu bellek bize çekirdek tarafından ayrıldı; kendimiz geri vermezsek
        // her saniye biraz daha sızdırırız.
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: tablo)),
                vm_size_t(tabloUzunluğu) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var tikler: [ÇekirdekTikleri] = []
        for çekirdek in 0 ..< Int(çekirdekSayısı) {
            // Sayaçlar tek bir düz dizide arka arkaya duruyor; her çekirdeğin
            // bloğu CPU_STATE_MAX kadar uzun.
            let taban = çekirdek * Int(CPU_STATE_MAX)
            tikler.append(ÇekirdekTikleri(
                kullanıcı:     Double(tablo[taban + Int(CPU_STATE_USER)]),
                sistem:        Double(tablo[taban + Int(CPU_STATE_SYSTEM)]),
                boşta:         Double(tablo[taban + Int(CPU_STATE_IDLE)]),
                düşükÖncelik:  Double(tablo[taban + Int(CPU_STATE_NICE)])
            ))
        }
        return tikler
    }
}
