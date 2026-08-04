import Foundation
import MacStatsCore

// ============================================================================
// SENSÖR TARAYICI (tanı aracı)
//
// Bu Mac'teki bütün sıcaklık sensörlerini ham hâliyle döker. Uygulamanın
// kendisi bunu kullanmaz; başka bir Mac modelinde sensör isimleri değişirse
// ya da sıcaklık okunamaz hâle gelirse ilk buna bakacağız.
//
// Kullanım:  swift run sensor-probe
// ============================================================================

print("macstats — sensör tarayıcı")
print(String(repeating: "=", count: 60))

let okuyucu = SıcaklıkOkuyucu()

guard let sıcaklıklar = okuyucu.oku() else {
    print("\nOKUNAMADI.")
    print("Bu macOS sürümünde sensörlere bu yoldan ulaşılamıyor demek.")
    exit(1)
}

let okumalar = sıcaklıklar.hamOkumalar
print("\n\(okumalar.count) sensör okundu (anlamsız değer veren sensörler zaten elenmiş durumda).\n")

// Aynı gruptaki sensörler bir arada dursun diye isimlerinin ilk kelimesine
// göre grupluyoruz: "pACC MTR Temp Sensor3" -> "pACC"
let gruplar = Dictionary(grouping: okumalar) {
    String($0.isim.split(separator: " ").first ?? "diğer")
}

for grup in gruplar.keys.sorted() {
    let üyeler = gruplar[grup]!.sorted { $0.isim < $1.isim }
    let enYüksek = üyeler.map(\.derece).max() ?? 0
    print("── \(grup)  (en yüksek: \(String(format: "%.1f", enYüksek)) °C)")
    for sensör in üyeler {
        print(String(format: "     %-30@ %6.1f °C", sensör.isim as NSString, sensör.derece))
    }
    print("")
}

print(String(repeating: "-", count: 60))
print("Uygulamanın kullandığı gruplar:")
print("  işlemci (hızlı+verimli en yüksek)  \(uzunSıcaklık(sıcaklıklar.işlemci))")
print("  hızlı çekirdekler   (pACC)         \(uzunSıcaklık(sıcaklıklar.hızlıÇekirdekler))")
print("  verimli çekirdekler (eACC)         \(uzunSıcaklık(sıcaklıklar.verimliÇekirdekler))")
print("  grafik              (GPU)          \(uzunSıcaklık(sıcaklıklar.grafik))")
print("  çip gövdesi         (SOC/PMGR)     \(uzunSıcaklık(sıcaklıklar.çipGövdesi))")
print("  depolama            (NAND)         \(uzunSıcaklık(sıcaklıklar.depolama))")
print("  pil                 (gas gauge)    \(uzunSıcaklık(sıcaklıklar.pil))")
