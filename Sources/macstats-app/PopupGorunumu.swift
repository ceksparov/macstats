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
        VStack(alignment: .leading, spacing: 10) {
            sıcaklıkBölümü
            Divider()
            işlemciBölümü
            Divider()
            bellekBölümü
            Divider()
            pilBölümü
            Divider()
            altBar
        }
        .padding(12)
        .frame(width: 330)
    }

    // MARK: - Alt bar
    //
    // "Girişte başlat" ve "Çık" eskiden ayrı NSMenuItem'lardı (NSMenu
    // döneminde). NSPopover'ın öyle bir liste kavramı yok — tek içerik
    // görünümü — o yüzden ikisi de panelin parçası.

    private var altBar: some View {
        HStack {
            Toggle("Girişte başlat", isOn: girişteBaşlatBağlantısı)
                .toggleStyle(.checkbox)
                .font(.callout)
            Spacer()
            Button("Çık") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.callout)
        }
    }

    /// GirişteBaşlat statik bir tip (SMAppService'in kendi durumunu okuyor),
    /// SwiftUI'a @State olarak taşımak yerine doğrudan onun üzerinden okuyup
    /// yazan bir Binding kuruyoruz. Onay işareti istenene değil GERÇEKLEŞENE
    /// göre kalıyor — kayıt başarısız olabilir (.app paketi dışından çalışırken).
    private var girişteBaşlatBağlantısı: Binding<Bool> {
        Binding(
            get: { GirişteBaşlat.açık },
            set: { GirişteBaşlat.ayarla($0) }
        )
    }

    // MARK: - Sıcaklık

    private var sıcaklıkBölümü: some View {
        let s = ölçüm?.sıcaklıklar

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("İşlemci")
                    .font(.headline)
                Spacer()
                Text(uzunSıcaklık(s?.işlemci, ondalık: 1))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(panelIsiRengi(s?.işlemci))
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

            // Apple'ın kendi termal değerlendirmesi. Sensör okuması bir gün
            // bozulsa bile bu resmî API çalışmaya devam eder; o yüzden burada.
            satır("Sistem durumu", ölçüm?.termal.rawValue ?? bilinmiyorİşareti)
        }
    }


    // MARK: - İşlemci

    private var işlemciBölümü: some View {
        let i = ölçüm?.işlemci

        return VStack(alignment: .leading, spacing: 6) {
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
                .frame(height: 22)
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

    /// Bellek ve pil, başlık + ayrı satır yerine tek satıra sığıyor.
    /// İkisi de tek sayı gösteriyor; iki satır ayırmak paneli gereksiz
    /// uzatıyordu. Sıcaklık bölümü büyük kalıyor, asıl bakılan yer o.
    private var bellekBölümü: some View {
        let b = ölçüm?.bellek
        let ayrıntı = b.map { "\(gigabayt($0.kullanılanBayt)) / \(gigabayt($0.toplamBayt))" }
        return sıkışıkSatır("Bellek", ayrıntı: ayrıntı, değer: yüzde(b?.kullanımYüzdesi))
    }

    // MARK: - Pil

    private var pilBölümü: some View {
        // Büyük sayı şarj döngüsü; sağlık yüzdesi kaldırılmıştı, döngü zaten
        // aynı hikâyeyi anlatıyor (M1 Air için sınır 1000).
        // Pil sıcaklığı da burada: sıcaklık bölümünde dururken işlemciyle
        // ilgiliymiş gibi görünüyordu.
        let döngü = ölçüm?.pil?.döngü.map { "\($0)" } ?? bilinmiyorİşareti
        return sıkışıkSatır(
            "Pil",
            ayrıntı: uzunSıcaklık(ölçüm?.sıcaklıklar?.pil),
            değer: döngü + " döngü"
        )
    }

    /// Başlık, küçük ayrıntı ve öne çıkan değer — hepsi tek satırda.
    private func sıkışıkSatır(_ başlık: String, ayrıntı: String?, değer: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(başlık)
                .font(.headline)
            Spacer()
            if let ayrıntı {
                Text(ayrıntı)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(değer)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
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
