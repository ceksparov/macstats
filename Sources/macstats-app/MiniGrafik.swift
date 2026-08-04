import SwiftUI
import MacStatsCore

// ============================================================================
// SON 60 SANİYENİN MİNİ GRAFİĞİ
//
// Sıcaklık çizgi olarak, işlemci yükü arkada soluk bir dolgu olarak çiziliyor.
//
// Neden ikisi bir arada: sıcaklık yükü gecikmeyle takip ediyor — yük bindikten
// ~12 saniye sonra sıcaklık tırmanmaya başlıyor, yük kalkınca da hemen değil
// yavaşça iniyor. Üst üste çizilince bu sebep-sonuç ilişkisi doğrudan görünür
// hâle geliyor; ayrı ayrı iki grafik aynı şeyi anlatamazdı.
// ============================================================================

struct MiniGrafik: View {
    let geçmiş: Geçmiş

    private let yükseklik: CGFloat = 58

    var body: some View {
        // Sıcaklığı okunamamış noktaları çizemeyiz; hepsini eleyince iki
        // noktadan az kalıyorsa çizecek bir şey yok demektir.
        let noktalar = geçmiş.noktalar.filter { $0.sıcaklık != nil }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Son 60 saniye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("çizgi: sıcaklık · dolgu: yük")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if noktalar.count < 2 {
                Text("Veri toplanıyor…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: yükseklik)
            } else {
                çizim(noktalar)
            }
        }
    }

    private func çizim(_ noktalar: [GeçmişNoktası]) -> some View {
        let sıcaklıklar = noktalar.compactMap(\.sıcaklık)
        let ölçek = grafikÖlçeği(sıcaklıklar) ?? GrafikÖlçeği(alt: 20, üst: 100)

        // Zaman eksenini son ölçüme göre sabitliyoruz. Date() kullansaydık
        // grafik her yeniden çizimde bir parça kayardı çünkü son ölçümün
        // üstünden geçen süre değişken.
        let son = noktalar[noktalar.count - 1].an
        let başlangıç = son.addingTimeInterval(-Geçmiş.pencereSaniye)

        // Çizim işi ayrı bir fonksiyonda: SwiftUI'ın görünüm kurucusu, içinde
        // yardımcı fonksiyon tanımlanan kapanışları kabul etmiyor.
        return GeometryReader { alan in
            eksenler(noktalar, ölçek: ölçek, başlangıç: başlangıç, boyut: alan.size)
        }
        .frame(height: yükseklik)
    }

    private func eksenler(
        _ noktalar: [GeçmişNoktası],
        ölçek: GrafikÖlçeği,
        başlangıç: Date,
        boyut: CGSize
    ) -> some View {
        let g = boyut.width
        let y = boyut.height

        // Zamandan yatay konuma
        let xKonum: (Date) -> CGFloat = { an in
            CGFloat(an.timeIntervalSince(başlangıç) / Geçmiş.pencereSaniye) * g
        }
        // Sıcaklıktan dikey konuma (ekranda yukarısı küçük sayı, o yüzden ters)
        let ySıcaklık: (Double) -> CGFloat = { derece in
            let oran = (derece - ölçek.alt) / (ölçek.üst - ölçek.alt)
            return y - CGFloat(oran) * y
        }
        // Yük her zaman 0–100 arası; sıcaklıkla aynı ölçeğe sokulmaz.
        let yYük: (Double) -> CGFloat = { yüzde in
            y - CGFloat(yüzde / 100) * y
        }

        return ZStack {
            yükDolgusu(noktalar, y: y, xKonum: xKonum, yYük: yYük)
            sıcaklıkÇizgisi(noktalar, xKonum: xKonum, ySıcaklık: ySıcaklık)
        }
        .overlay(alignment: .topTrailing) {
            // Ölçeğin ne olduğu görünmezse grafik yanıltıcı olur.
            Text(uzunSıcaklık(ölçek.üst))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(uzunSıcaklık(ölçek.alt))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func yükDolgusu(
        _ noktalar: [GeçmişNoktası],
        y: CGFloat,
        xKonum: @escaping (Date) -> CGFloat,
        yYük: @escaping (Double) -> CGFloat
    ) -> some View {
        Path { yol in
            let yüklü = noktalar.filter { $0.yük != nil }
            guard let ilk = yüklü.first, let sonuncu = yüklü.last else { return }

            yol.move(to: CGPoint(x: xKonum(ilk.an), y: y))
            for nokta in yüklü {
                yol.addLine(to: CGPoint(x: xKonum(nokta.an), y: yYük(nokta.yük!)))
            }
            yol.addLine(to: CGPoint(x: xKonum(sonuncu.an), y: y))
            yol.closeSubpath()
        }
        .fill(Color.accentColor.opacity(0.16))
    }

    private func sıcaklıkÇizgisi(
        _ noktalar: [GeçmişNoktası],
        xKonum: @escaping (Date) -> CGFloat,
        ySıcaklık: @escaping (Double) -> CGFloat
    ) -> some View {
        // Çizginin rengi en son ölçüme göre; menü barındaki renkle aynı mantık.
        let sonDeğer = noktalar[noktalar.count - 1].sıcaklık
        let çizgiRengi: Color = {
            switch sıcaklıkSeviyesi(sonDeğer) {
            case .serin: return .primary
            case .ılık: return .orange
            case .sıcak: return .red
            case .bilinmiyor: return .secondary
            }
        }()

        return Path { yol in
            for (sıra, nokta) in noktalar.enumerated() {
                let konum = CGPoint(x: xKonum(nokta.an), y: ySıcaklık(nokta.sıcaklık!))
                if sıra == 0 { yol.move(to: konum) } else { yol.addLine(to: konum) }
            }
        }
        .stroke(çizgiRengi, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}
