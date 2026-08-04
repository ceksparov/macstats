import AppKit

// ============================================================================
// UYGULAMANIN GİRİŞ NOKTASI
// ============================================================================

final class UygulamaTemsilcisi: NSObject, NSApplicationDelegate {
    // Menü barındaki gösterge. Burada saklamamızın sebebi teknik: değişkeni
    // tutmazsak Swift onu gereksiz sanıp bellekten atar ve ikon menü barından
    // kaybolur.
    private var durumÇubuğu: DurumÇubuğu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bu metot her zaman ana iş parçacığında çağrılır; assumeIsolated
        // derleyiciye bunu söylüyor. Arayüze dokunan her şey orada olmak zorunda.
        MainActor.assumeIsolated {
            durumÇubuğu = DurumÇubuğu()
        }
    }
}

let uygulama = NSApplication.shared

// .accessory = Dock'ta ikon gösterme, uygulama değiştiricide (cmd-tab) çıkma.
// Bu uygulamanın yeri sadece menü barı.
uygulama.setActivationPolicy(.accessory)

let temsilci = UygulamaTemsilcisi()
uygulama.delegate = temsilci
uygulama.run()
