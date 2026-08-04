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

/// Depoyu izleyen ince sarmalayıcı. İçeriği ayrı tutuyoruz ki görünüm canlı
/// donanıma bağlı olmadan da (örnek verilerle) çizilebilsin — böylece
/// tasarımı denemek için uygulamayı çalıştırıp tıklamak gerekmiyor.
struct PopupGörünümü: View {
    @ObservedObject var depo: ÖlçümDeposu

    var body: some View {
        Popupİçeriği(ölçüm: depo.ölçüm, geçmiş: depo.geçmiş)
    }
}

struct Popupİçeriği: View {
    let ölçüm: Ölçüm?
    let geçmiş: Geçmiş

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sıcaklıkBölümü
            Divider()
            işlemciBölümü
            Divider()
            bellekBölümü
            Divider()
            pilBölümü
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Sıcaklık

    private var sıcaklıkBölümü: some View {
        let s = ölçüm?.sıcaklıklar

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

            // Grafik doğrudan büyük sayının altında: tek bir sayı "58 °C" der
            // ama "tırmanıyor mu, oturdu mu" sorusunu cevaplamaz. Grafiğin
            // işi o soruyu cevaplamak, o yüzden sayıya bitişik duruyor.
            MiniGrafik(geçmiş: geçmiş)
                .padding(.vertical, 2)

            // İşlemci için tek bir sayı gösteriyoruz. Hızlı/verimli çekirdek,
            // çip gövdesi ve SSD ayrımları ölçülmeye devam ediyor (Sıcaklıklar
            // içinde duruyorlar) ama ekranda yer kaplamalarına değmiyor:
            // hepsi birkaç derece aralıkta oynayan, aynı hikâyeyi anlatan
            // sayılar. GPU ve pil ise gerçekten ayrı bileşen, onlar kalıyor.
            satır("Grafik (GPU)", uzunSıcaklık(s?.grafik))
            satır("Pil", uzunSıcaklık(s?.pil))

            // Apple'ın kendi termal değerlendirmesi. Sensör okuması bir gün
            // bozulsa bile bu resmî API çalışmaya devam eder; o yüzden burada.
            satır("Sistem durumu", ölçüm?.termal.rawValue ?? bilinmiyorİşareti)
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
        let i = ölçüm?.işlemci

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
                // Tek bir yüzde yeterli. "Uygulamalar / sistem" ayrımı
                // ölçülmeye devam ediyor (terminal aracında görünüyor), ama
                // menü barından bakan biri için gereksiz ayrıntıydı.

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
            ZStack(alignment: .bottom) {
                // Arka şerit: dolu kısım olmadan çubuklar düşük yükte havada
                // asılı çizgiler gibi görünüyordu; şerit sayesinde her
                // çekirdeğin nereye kadar dolabileceği belli oluyor.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.08))

                RoundedRectangle(cornerRadius: 2)
                    .fill(çubukRengi)
                    // En düşük yükte bile ince bir iz kalsın.
                    .frame(height: max(2, alan.size.height * yüzde / 100))
            }
        }
    }

    /// Grafikteki yük dolgusuyla aynı mavi. Sistem vurgu rengi kullanıcıya
    /// göre gri olabiliyor ve o zaman çubuklar kayboluyordu.
    private var çubukRengi: Color { Color(red: 0.25, green: 0.55, blue: 1.0) }

    // MARK: - Bellek

    private var bellekBölümü: some View {
        let b = ölçüm?.bellek

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bellek")
                    .font(.headline)
                Spacer()
                Text(yüzde(b?.kullanımYüzdesi))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }

            // Tek satır: kullanılan / toplam. Kırılım (uygulamalar, kilitli,
            // sıkıştırılmış, swap) ölçülmeye devam ediyor ve terminal
            // aracında görünüyor; menü bar penceresinde yer kaplamasına değmez.
            if let b {
                satır("Kullanılan", "\(gigabayt(b.kullanılanBayt)) / \(gigabayt(b.toplamBayt))")
            } else {
                Text(bilinmiyorİşareti).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pil

    private var pilBölümü: some View {
        let p = ölçüm?.pil

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pil")
                    .font(.headline)
                Spacer()
                // Sağlık = bugünkü kapasite / fabrika kapasitesi. Şarj
                // seviyesini göstermiyoruz; onu macOS zaten menü barında
                // gösteriyor, burada tekrar etmenin anlamı yok.
                Text(yüzde(p?.sağlıkYüzdesi))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            satır("Şarj döngüsü", p?.döngü.map(String.init) ?? bilinmiyorİşareti)
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
