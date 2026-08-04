// swift-tools-version: 5.9
// macstats — M1 Mac'ler için menü bar sistem göstergesi.

import PackageDescription

let package = Package(
    name: "macstats",
    platforms: [
        // MenuBarExtra (menü barda pencere açan bileşen) macOS 13 ile geldi.
        .macOS(.v13)
    ],
    targets: [
        // Ölçüm katmanı. Ekranla hiçbir ilgisi yok, sadece sayı üretir.
        // Menü bar uygulaması da, aşağıdaki terminal araçları da bunu kullanır.
        .target(name: "MacStatsCore"),

        // Terminalde canlı ölçüm gösteren araç. Menü bar arayüzü yazılmadan
        // önce sayıların doğru olduğunu burada doğruluyoruz.
        .executableTarget(name: "macstats-cli", dependencies: ["MacStatsCore"]),

        // Tanı aracı: bu Mac'teki bütün sıcaklık sensörlerini ham hâliyle döker.
        // Başka bir modelde sensör isimleri değişirse ilk buna bakacağız.
        .executableTarget(name: "sensor-probe", dependencies: ["MacStatsCore"]),

        // Sadece saf mantık test ediliyor (hesaplama, biçimlendirme).
        // Donanım okuyan kısımlar test edilemez, çünkü sonuç makineye göre değişir.
        .testTarget(name: "MacStatsCoreTests", dependencies: ["MacStatsCore"]),
    ]
)
