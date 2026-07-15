# Zánka táborfigyelő – Windy plugin v0.5

## Indítás Macen

1. Csomagold ki a ZIP-et.
2. Dupla kattintás a `start.command` fájlra.
3. Ha a macOS blokkolja: jobb kattintás → Megnyitás.
4. A Windy Developer Mode-ban töltsd be:

   `https://localhost:9999/plugin.js`

## Beépített funkciók

- Fix táborpolygon, kék középpont és 30 km-es kör.
- A Windy logóhoz igazodó, folyamatosan látható Dynamic Island.
- Fix 30 px magasság; push értesítésnél csak a szélessége változik, középről két irányba.
- A notch alatt három kör alakú balatoni viharjelző ikon (0, I., II. fok), medencenevekkel.
- OKF balatoni viharjelzés lekérés; hang csak a középső medence változásakor.
- Veszprém vármegye tűzgyújtási tilalom ellenőrzése.
- Fejlesztői tesztgombok: I/II. fok, 30 km-es zóna, tábor érintett, tűztilalom, HungaroMet.
- A portál-elemek közvetlenül a `document.body` alatt futnak, és a plugin aktív állapotában újrarendereléskor is visszakerülnek.

## Megjegyzés

A 30 km-es zóna és a tábor területének zivatar általi átlépése ebben a csomagban tesztértesítésként szerepel. Az automatikus éles riasztáshoz külön radar- vagy villámadat-forrás bekötése szükséges.
