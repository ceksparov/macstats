import Foundation

// ============================================================================
// BELLEK (RAM)
//
// Buradaki her şey de resmî API. Sıcaklık gibi kırılgan değil.
//
// EN ÖNEMLİ NOKTA: macOS boş RAM'i israf sayar. Kullanmadığın belleği önbellek
// olarak doldurur ve ihtiyaç olunca anında boşaltır. Bu yüzden "RAM %88 dolu"
// yazısı hiçbir şey ifade etmez — makine sağlıklıyken de öyle görünür.
//
// Asıl bilgi "bellek baskısı": macOS'un kendi verdiği, sistem gerçekten
// zorlanıyor mu sorusunun cevabı. Yüzdeyi de gösteriyoruz ama tek başına değil.
// ============================================================================


/// macOS'un bellek durumu hakkındaki kendi kararı.
public enum BellekBaskısı: Sendable {
    case normal      // her şey yolunda
    case uyarı       // sistem sıkışmaya başladı, sıkıştırma/swap devrede
    case kritik      // ciddi darlık, uygulamalar yavaşlıyor
    case bilinmiyor  // okuyamadık — sayı uydurmaktansa bunu göstermek daha dürüst

    /// Çekirdeğin döndürdüğü ham sayıyı anlamlı hâle çevirir.
    /// Değerler işletim sisteminin bellek baskısı bildirimleriyle aynı:
    /// 1 = normal, 2 = uyarı, 4 = kritik.
    public static func hamDeğerden(_ ham: Int32) -> BellekBaskısı {
        switch ham {
        case 1: return .normal
        case 2: return .uyarı
        case 4: return .kritik
        default: return .bilinmiyor
        }
    }
}


/// Çekirdekten okunan ham sayfa sayıları.
/// Bellek "sayfa" denen eşit bloklar hâlinde yönetilir; bu Mac'te bir sayfa
/// 16 KB. Bayta çevirmek için sayfa boyutuyla çarpıyoruz.
public struct SayfaSayıları: Sendable {
    public let dahili: UInt64          // uygulamaların tuttuğu bellek
    public let temizlenebilir: UInt64  // istendiği an atılabilen kısım
    public let kilitli: UInt64         // diske atılamaz, çekirdeğin ihtiyacı (wired)
    public let sıkıştırılmış: UInt64   // yer açmak için sıkıştırılmış bellek

    public init(dahili: UInt64, temizlenebilir: UInt64, kilitli: UInt64, sıkıştırılmış: UInt64) {
        self.dahili = dahili
        self.temizlenebilir = temizlenebilir
        self.kilitli = kilitli
        self.sıkıştırılmış = sıkıştırılmış
    }
}

/// Activity Monitor'ün "Kullanılan Bellek" değerini hesaplar.
///
/// Formül: (uygulama belleği − temizlenebilir) + kilitli + sıkıştırılmış
///
/// Temizlenebilir kısmı düşüyoruz çünkü o bellek teknik olarak dolu görünse de
/// sistem istediği an geri alabiliyor; kullanıcı açısından "dolu" sayılmaz.
///
/// Saf bir fonksiyon olarak ayrı duruyor ki test edilebilsin — donanım okuyan
/// kodun aksine bunun doğruluğu makineye bağlı değil.
public func kullanılanBellekBaytı(_ sayfalar: SayfaSayıları, sayfaBoyutu: UInt64) -> UInt64 {
    let uygulama = sayfalar.dahili >= sayfalar.temizlenebilir
        ? sayfalar.dahili - sayfalar.temizlenebilir
        : 0  // Ölçümler aynı ana ait olmadığı için teoride ters düşebilir.
    return (uygulama + sayfalar.kilitli + sayfalar.sıkıştırılmış) * sayfaBoyutu
}


/// Bir ölçüm anındaki bellek durumu.
public struct BellekDurumu: Sendable {
    public let toplamBayt: UInt64
    public let uygulamaBayt: UInt64
    public let kilitliBayt: UInt64
    public let sıkıştırılmışBayt: UInt64
    public let kullanılanBayt: UInt64
    public let swapKullanılanBayt: UInt64
    public let baskı: BellekBaskısı

    /// 0–100. Yanında baskı göstergesi olmadan tek başına gösterilmemeli.
    public var kullanımYüzdesi: Double {
        guard toplamBayt > 0 else { return 0 }
        return Double(kullanılanBayt) / Double(toplamBayt) * 100
    }
}


public struct BellekOkuyucu {

    public init() {}

    public func oku() -> BellekDurumu? {
        guard let sayfalar = sayfaSayılarınıOku() else { return nil }

        let sayfaBoyutu = UInt64(vm_kernel_page_size)
        let uygulama = sayfalar.dahili >= sayfalar.temizlenebilir
            ? sayfalar.dahili - sayfalar.temizlenebilir
            : 0

        return BellekDurumu(
            toplamBayt: ProcessInfo.processInfo.physicalMemory,
            uygulamaBayt: uygulama * sayfaBoyutu,
            kilitliBayt: sayfalar.kilitli * sayfaBoyutu,
            sıkıştırılmışBayt: sayfalar.sıkıştırılmış * sayfaBoyutu,
            kullanılanBayt: kullanılanBellekBaytı(sayfalar, sayfaBoyutu: sayfaBoyutu),
            swapKullanılanBayt: swapKullanımınıOku(),
            baskı: baskıyıOku()
        )
    }

    private func sayfaSayılarınıOku() -> SayfaSayıları? {
        var istatistik = vm_statistics64_data_t()
        // Çekirdek bu yapıyı "kaç tane 32-bit tamsayı" olarak ölçer, bayt olarak değil.
        var uzunluk = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let sonuç = withUnsafeMutablePointer(to: &istatistik) { yapı in
            yapı.withMemoryRebound(to: integer_t.self, capacity: Int(uzunluk)) { dizi in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, dizi, &uzunluk)
            }
        }
        guard sonuç == KERN_SUCCESS else { return nil }

        return SayfaSayıları(
            dahili: UInt64(istatistik.internal_page_count),
            temizlenebilir: UInt64(istatistik.purgeable_count),
            kilitli: UInt64(istatistik.wire_count),
            sıkıştırılmış: UInt64(istatistik.compressor_page_count)
        )
    }

    /// Diske taşınmış bellek miktarı. 8 GB'lık bir makinede bu sayının
    /// büyümesi, RAM yüzdesinden çok daha net bir "yetmiyor" işareti.
    private func swapKullanımınıOku() -> UInt64 {
        var kullanım = xsw_usage()
        var uzunluk = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &kullanım, &uzunluk, nil, 0) == 0 else { return 0 }
        return kullanım.xsu_used
    }

    private func baskıyıOku() -> BellekBaskısı {
        var seviye: Int32 = 0
        var uzunluk = MemoryLayout<Int32>.stride
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &seviye, &uzunluk, nil, 0) == 0
        else { return .bilinmiyor }
        return BellekBaskısı.hamDeğerden(seviye)
    }
}
