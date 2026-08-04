import SwiftUI
import MacStatsCore

// ============================================================================
// SON 60 SANİYENİN MİNİ GRAFİĞİ
//
// Sıcaklık çizgi olarak, işlemci yükü arkada dolgu olarak çiziliyor.
//
// Neden ikisi bir arada: sıcaklık yükü gecikmeyle takip ediyor — yük bindikten
// ~12 saniye sonra sıcaklık tırmanmaya başlıyor, yük kalkınca da hemen değil
// yavaşça iniyor. Üst üste çizilince bu sebep-sonuç ilişkisi doğrudan görünür.
//
// Okunaklılık kararları (ilk sürüm okunmuyordu):
//   - Grafik alanı 58 -> 124 piksel; kısa bir şeritte eğri okunmuyordu.
//   - Derece etiketleri artık grafiğin İÇİNDE değil, solunda kendi sütununda;
//     üstte ve altta uçuşan 9 puntoluk gri yazılar seçilmiyordu.
//   - Yük dolgusu %16 saydamlıktan %38'e çıktı ve üstüne ince bir çizgi eklendi;
//     ayrıca sistem vurgu rengi yerine sabit mavi kullanılıyor — kullanıcının
//     vurgu rengi griyse dolgu tamamen kayboluyordu.
//   - Arkaya yatay ızgara çizgileri ve alana çerçeve eklendi ki grafiğin nerede
//     başlayıp bittiği belli olsun.
// ============================================================================

struct MiniGrafik: View {
    let geçmiş: Geçmiş

    private let alanYüksekliği: CGFloat = 124
    private let etiketGenişliği: CGFloat = 34

    // Sistem vurgu rengi kullanıcıya göre gri olabiliyor; dolgunun görünmesi
    // buna bağlı kalmamalı.
    private let yükRengi = Color(red: 0.25, green: 0.55, blue: 1.0)

    var body: some View {
        let noktalar = geçmiş.noktalar.filter { $0.sıcaklık != nil }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Son 60 saniye")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                gösterge(renk: .primary, yazı: "sıcaklık")
                gösterge(renk: yükRengi, yazı: "yük")
            }

            if noktalar.count < 2 {
                Text("Veri toplanıyor…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: alanYüksekliği)
            } else {
                çizim(noktalar)
            }
        }
    }

    private func gösterge(renk: Color, yazı: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1)
                .fill(renk)
                .frame(width: 10, height: 3)
            Text(yazı)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func çizim(_ noktalar: [GeçmişNoktası]) -> some View {
        let sıcaklıklar = noktalar.compactMap(\.sıcaklık)
        let ölçek = grafikÖlçeği(sıcaklıklar) ?? GrafikÖlçeği(alt: 20, üst: 100)

        // Zaman eksenini son ölçüme göre sabitliyoruz. Date() kullansaydık
        // grafik her yeniden çizimde bir parça kayardı.
        let son = noktalar[noktalar.count - 1].an
        let başlangıç = son.addingTimeInterval(-Geçmiş.pencereSaniye)
        let orta = (ölçek.alt + ölçek.üst) / 2

        return HStack(spacing: 6) {
            // Derece etiketleri kendi sütununda: grafiğin üstüne bindirilince
            // çizgiyle karışıp okunmuyorlardı.
            VStack(alignment: .trailing) {
                etiket(ölçek.üst)
                Spacer()
                etiket(orta)
                Spacer()
                etiket(ölçek.alt)
            }
            .frame(width: etiketGenişliği, height: alanYüksekliği)

            GeometryReader { alan in
                eksenler(noktalar, ölçek: ölçek, başlangıç: başlangıç, boyut: alan.size)
            }
            .frame(height: alanYüksekliği)
        }
    }

    private func etiket(_ derece: Double) -> some View {
        Text(uzunSıcaklık(derece))
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    private func eksenler(
        _ noktalar: [GeçmişNoktası],
        ölçek: GrafikÖlçeği,
        başlangıç: Date,
        boyut: CGSize
    ) -> some View {
        let g = boyut.width
        let y = boyut.height

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
            ızgara(y: y)
            yükDolgusu(noktalar, y: y, xKonum: xKonum, yYük: yYük)
            yükÇizgisi(noktalar, xKonum: xKonum, yYük: yYük)
            sıcaklıkÇizgisi(noktalar, xKonum: xKonum, ySıcaklık: ySıcaklık)
        }
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Ortadaki yatay çizgi: gözün eğriyi bir yere göre okuyabilmesi için.
    private func ızgara(y: CGFloat) -> some View {
        Path { yol in
            yol.move(to: CGPoint(x: 0, y: y / 2))
            yol.addLine(to: CGPoint(x: 10_000, y: y / 2))
        }
        .stroke(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
        .fill(yükRengi.opacity(0.38))
    }

    /// Dolgunun üst kenarına ince bir çizgi: dolgu tek başına sınırı belirsiz
    /// bırakıyor, yükün tam olarak nereye çıktığı seçilmiyordu.
    private func yükÇizgisi(
        _ noktalar: [GeçmişNoktası],
        xKonum: @escaping (Date) -> CGFloat,
        yYük: @escaping (Double) -> CGFloat
    ) -> some View {
        Path { yol in
            let yüklü = noktalar.filter { $0.yük != nil }
            for (sıra, nokta) in yüklü.enumerated() {
                let konum = CGPoint(x: xKonum(nokta.an), y: yYük(nokta.yük!))
                if sıra == 0 { yol.move(to: konum) } else { yol.addLine(to: konum) }
            }
        }
        .stroke(yükRengi.opacity(0.85), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
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
        .stroke(çizgiRengi, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
    }
}
