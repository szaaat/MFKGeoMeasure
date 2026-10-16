# MFK GeoMeasure Magasság- és Koordináta-kezelési Jelentés

A feladatok elvégzése megtörtént, a BME-rácsos magasságkezelés és koordinátatranszformáció tovább lett finomítva a kéréseknek megfelelően.

## 1. Magasságkezelés végigvezetése
- A telefonos belső GPS (`InternalGnssProvider`) mostantól minden platformon (Android és iOS is) egyaránt ellipszoidi forrásmagasságot (`isEllipsoidal = true`) rögzít, hiszen a geolocator (és az alatta lévő rendszer API-k) WGS84 ellipszoid feletti magasságot adnak vissza.
- Megszüntettük a `Platform.isAndroid` automatikus és pontatlan magasságtípus-becslését.
- Az `MFKRTK/Bynav` és az NMEA parserek továbbra is a kapott `isEllipsoidal` vagy `MSL` értékek alapján határozzák meg a típust.
- Ha a pont forrásmagassága már ortometrikus, a rendszer **nem alkalmaz rá ismételt geoidkorrekciót**.
- Amennyiben a magasság ellipszoidi és a BME rácson belül található (függetlenül a referencia kerettől), a Balti magasság kiszámításra kerül a `BME_geoid2014` modell használatával. Ismeretlen keret esetén a `heightReferenceStatus` automatikusan `assumed` értéket kap a mentett adatokban (`GeoFeature.properties`).
- Mentésnél (`ProjectService`) a forrásmagasság (Ellipszoidi) minden esetben megőrzésre kerül, és mellette egyértelműen rögzítésre kerül a számított Balti magasság, a használt geoid modell (`Geoid_Model`), valamint a magassági referencia státusza (`Height_Reference_Frame`).

## 2. Automatikus legacy fallback megszüntetése
- Az `eovToWgs()` (és a `transformEovToWgs()` belső hívás) mostantól egyértelmű `outsideGrid` státuszt vagy hibát ad vissza, ha a pont a BME-rácson kívül esik, és **nem esik vissza automatikusan a `+towgs84` Helmert transzformációra**.
- A régi, pontatlan transzformáció csak kifejezett konfigurációs beállítás (`EovTransformMode.legacy`) esetén használható.
- Ez az élő térképi konverziónál, az exportoknál (SHP, CSV, GeoJSON) és a manuális pontbevitelnél is egyaránt kezelt (`MapScreen`, `ProjectService`).

## Tesztelés és Ellenőrzés
Két új dedikált tesztfájl készült, amelyek az alábbiakat igazolják:
1. `height_management_test.dart`:
   - Ellipszoidi magasságok geoid korrekciója ismeretlen (assumed) és ETRF2000 keretek esetén a BME rács használatával.
   - Már ortometrikus (Balti/MSL) magasságok intakt hagyása (korrekció mellőzése).
2. `eov_service_fallback_test.dart`:
   - A `towgs84` transzformáció automatikus aktiválódásának teljes hiánya BME-rács határain kívül, megfelelő hibakezeléssel (StateError / EovTransformStatus.outsideGrid).

### Ami még terepi ellenőrzést igényel
A tesztcsomag (bár szintaktikailag és egységteszt szinten validált) sikeresen lefutott, de az alábbi funkciók **valós, terepi tesztelést** igényelnek MFKRTK / Bynav műszerrel:
- Valós RTK fixek mellett a `Bynav/MFKRTK` NMEA mondataiból kinyert magasságok (ortometrikus vs. ellipszoidi flagek) helyes beazonosítása és rögzítése az attribútumtáblában.
- Terepi pontfelvételek (vonalak, poligonok rögzítése esetén is) Balti magasságainak ellenőrzése egy ismert geodéziai alapponton (hogy az `assumed` ETRF2000 és a `BME_geoid2014` párosítása metrikusan pontos-e a valóságban).
