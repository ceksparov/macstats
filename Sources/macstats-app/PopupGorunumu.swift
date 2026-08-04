import SwiftUI
import MacStatsCore

// ============================================================================
// TIKLAYINCA AÇILAN PENCERE
//
// Şimdilik kasıtlı olarak sade: amaç sayıların doğru göründüğünü doğrulamak.
// Tasarım sonra giydirilecek, o yüzden burada renk/ölçü kararları en aza
// indirildi ve sistemin kendi renkleri kullanıldı (karanlık moda kendiliğinden
// uyum sağlasın diye).
// ============================================================================

struct PopupGörünümü: View {
    @ObservedObject var depo: ÖlçümDeposu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sıcaklıkBölümü
            Divider()
            işlemciBölümü
            Divider()
            bellekBölümü
            Divider()
            altBar
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Sıcaklık

    private var sıcaklıkBölümü: some View {
        let s = depo.ölçüm?.sıcaklıklar

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("İşlemci")
                    .font(.headline)
                Spacer()
                Text(uzunSıcaklık(s?.işlemci))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(sıcaklıkRengi(sıcaklıkSeviyesi(s?.işlemci)))
            }

            // İşlemci için tek bir sayı gösteriyoruz. Hızlı/verimli çekirdek,
            // çip gövdesi ve SSD ayrımları ölçülmeye devam ediyor (Sıcaklıklar
            // içinde duruyorlar) ama ekranda yer kaplamalarına değmiyor:
            // hepsi birkaç derece aralıkta oynayan, aynı hikâyeyi anlatan
            // sayılar. GPU ve pil ise gerçekten ayrı bileşen, onlar kalıyor.
            satır("Grafik (GPU)", uzunSıcaklık(s?.grafik))
            satır("Pil", uzunSıcaklık(s?.pil))

            // Apple'ın kendi termal değerlendirmesi. Sensör okuması bir gün
            // bozulsa bile bu resmî API çalışmaya devam eder; o yüzden burada.
            satır("Sistem durumu", depo.ölçüm?.termal.rawValue ?? bilinmiyorİşareti)
        }
    }

    private func sıcaklıkRengi(_ seviye: SıcaklıkSeviyesi) -> Color {
        switch seviye {
        case .serin: return .primary
        case .ılık: return .orange
        case .sıcak: return .red
        case .bilinmiyor: return .secondary
        }
    }

    // MARK: - İşlemci

    private var işlemciBölümü: some View {
        let i = depo.ölçüm?.işlemci

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Kullanım")
                    .font(.headline)
                Spacer()
                Text(yüzde(i?.toplamYüzde))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }

            if let i {
                satır("Uygulamalar", yüzde(i.kullanıcıYüzde))
                satır("Sistem", yüzde(i.sistemYüzde))

                // M1'de 8 çekirdek: ilk 4'ü verimlilik, son 4'ü performans.
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(i.çekirdekYüzdeleri.enumerated()), id: \.offset) { _, yüzde in
                        çekirdekÇubuğu(yüzde)
                    }
                }
                .frame(height: 26)
            }
        }
    }

    private func çekirdekÇubuğu(_ yüzde: Double) -> some View {
        GeometryReader { alan in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    // En düşük yükte bile ince bir iz kalsın ki kaç çekirdek
                    // olduğu görünsün.
                    .frame(height: max(2, alan.size.height * yüzde / 100))
            }
        }
    }

    // MARK: - Bellek

    private var bellekBölümü: some View {
        let b = depo.ölçüm?.bellek

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bellek")
                    .font(.headline)
                Spacer()
                // Baskı yüzdeden ÖNCE ve daha görünür duruyor. Sebep: yüzde
                // tek başına yanıltıcı — bu makinede %72 görünürken sistem
                // uyarı seviyesinde olabiliyor.
                Text(baskıAdı(b?.baskı ?? .bilinmiyor))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(baskıRengi(b?.baskı ?? .bilinmiyor).opacity(0.18))
                    .foregroundStyle(baskıRengi(b?.baskı ?? .bilinmiyor))
                    .clipShape(Capsule())
            }

            if let b {
                satır("Kullanılan",
                      "\(gigabayt(b.kullanılanBayt)) / \(gigabayt(b.toplamBayt))  (\(yüzde(b.kullanımYüzdesi)))")
                satır("Uygulamalar", gigabayt(b.uygulamaBayt))
                satır("Kilitli", gigabayt(b.kilitliBayt))
                satır("Sıkıştırılmış", gigabayt(b.sıkıştırılmışBayt))
                satır("Swap (diskte)", gigabayt(b.swapKullanılanBayt))
            } else {
                Text(bilinmiyorİşareti).foregroundStyle(.secondary)
            }
        }
    }

    private func baskıAdı(_ baskı: BellekBaskısı) -> String {
        switch baskı {
        case .normal: return "NORMAL"
        case .uyarı: return "UYARI"
        case .kritik: return "KRİTİK"
        case .bilinmiyor: return bilinmiyorİşareti
        }
    }

    private func baskıRengi(_ baskı: BellekBaskısı) -> Color {
        switch baskı {
        case .normal: return .green
        case .uyarı: return .orange
        case .kritik: return .red
        case .bilinmiyor: return .secondary
        }
    }

    // MARK: - Alt bar

    private var altBar: some View {
        HStack {
            Text("macstats")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Çık") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    // MARK: - Ortak satır biçimi

    private func satır(_ etiket: String, _ değer: String) -> some View {
        HStack {
            Text(etiket)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(değer)
                .font(.callout)
                .monospacedDigit()
        }
    }
}
