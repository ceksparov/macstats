import Foundation
import MacStatsCore

// ============================================================================
// TERMİNAL ARACI
//
// Menü bar arayüzü yazılmadan önce sayıların doğru olduğunu burada
// doğruluyoruz. Uygulamanın kendisi değil, ölçüm katmanının vitrini.
//
// Kullanım:  swift run macstats-cli [kaç kez ölçsün]
// ============================================================================

let kaçKez = CommandLine.arguments.count > 1 ? (Int(CommandLine.arguments[1]) ?? 5) : 5

let toplayıcı = ÖlçümToplayıcı(tümSensörler: true)   // tanı aracı: kırılımın tamamı

print("macstats — canlı ölçüm (\(kaçKez) örnek, saniyede bir)")
print(String(repeating: "=", count: 64))

for sıra in 1 ... kaçKez {
    let ölçüm = toplayıcı.ölç()

    print("\n[\(sıra)/\(kaçKez)]  \(zamanDamgası(ölçüm.an))")
    print(String(repeating: "-", count: 64))

    // --- Sıcaklık ---
    let s = ölçüm.sıcaklıklar
    print("SICAKLIK")
    print("  İşlemci (menü barda görünecek olan)  \(uzunSıcaklık(s?.işlemci))"
        + "   [\(seviyeAdı(sıcaklıkSeviyesi(s?.işlemci)))]")
    print("    hızlı çekirdekler                  \(uzunSıcaklık(s?.hızlıÇekirdekler))")
    print("    verimli çekirdekler                \(uzunSıcaklık(s?.verimliÇekirdekler))")
    print("  Grafik (GPU)                         \(uzunSıcaklık(s?.grafik))")
    print("  Çip gövdesi                          \(uzunSıcaklık(s?.çipGövdesi))")
    print("  Depolama (SSD)                       \(uzunSıcaklık(s?.depolama))")
    print("  Pil                                  \(uzunSıcaklık(s?.pil))")
    print("  Apple'ın termal değerlendirmesi      \(ölçüm.termal.rawValue)")

    // --- İşlemci ---
    print("İŞLEMCİ")
    if let i = ölçüm.işlemci {
        print("  Toplam kullanım                      \(yüzde(i.toplamYüzde))"
            + "   (uygulamalar \(yüzde(i.kullanıcıYüzde)), sistem \(yüzde(i.sistemYüzde)))")
        print("  Çekirdek başına                      \(çubuklar(i.çekirdekYüzdeleri))")
    } else {
        // İlk ölçümde normal: yüzde iki ölçümün farkından çıkıyor.
        print("  \(bilinmiyorİşareti) (ilk ölçüm — karşılaştıracak öncesi yok)")
    }

    // --- Bellek ---
    print("BELLEK")
    if let b = ölçüm.bellek {
        print("  Kullanılan                           \(gigabayt(b.kullanılanBayt))"
            + " / \(gigabayt(b.toplamBayt))   (\(yüzde(b.kullanımYüzdesi)))")
        print("    uygulamalar                        \(gigabayt(b.uygulamaBayt))")
        print("    kilitli (çekirdek)                 \(gigabayt(b.kilitliBayt))")
        print("    sıkıştırılmış                      \(gigabayt(b.sıkıştırılmışBayt))")
        print("  Swap (diske taşınan)                 \(gigabayt(b.swapKullanılanBayt))")
    } else {
        print("  \(bilinmiyorİşareti) okunamadı")
    }

    if sıra < kaçKez {
        Thread.sleep(forTimeInterval: 1.0)
    }
}


// MARK: - Sadece bu araca ait küçük yardımcılar

func zamanDamgası(_ an: Date) -> String {
    let biçim = DateFormatter()
    biçim.dateFormat = "HH:mm:ss"
    return biçim.string(from: an)
}

func seviyeAdı(_ seviye: SıcaklıkSeviyesi) -> String {
    switch seviye {
    case .serin: return "serin"
    case .ılık: return "ılık"
    case .sıcak: return "sıcak"
    case .bilinmiyor: return bilinmiyorİşareti
    }
}


/// Çekirdek yüzdelerini gözle görülebilir küçük çubuklara çevirir.
func çubuklar(_ yüzdeler: [Double]) -> String {
    let kademeler = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    return yüzdeler.map { yüzde in
        let indeks = min(kademeler.count - 1, max(0, Int(yüzde / 100 * Double(kademeler.count))))
        return kademeler[indeks]
    }.joined(separator: " ")
}
