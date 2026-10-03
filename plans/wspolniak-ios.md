# Plan: Wspólniak for iOS & iPadOS

> Source PRD: [PRD.md](../PRD.md) — natywna aplikacja Wspólniaka (SwiftUI, iPhone + iPad,
> dystrybucja Unlisted App Store). Powiązane repo: `CrystalPlatforms/wspolniak` (backend),
> `CrystalPlatforms/wspolniak-android` (odpowiednik Androida, po zakończeniu iOS).

## Issues (GitHub)

Każda faza = jedno issue w `CrystalPlatforms/wspolniak-ios` (indeks: komentarz na issue [#1](https://github.com/CrystalPlatforms/wspolniak-ios/issues/1)):

| Faza | Issue | Typ |
|---|---|---|
| 1. Fundament | [#2](https://github.com/CrystalPlatforms/wspolniak-ios/issues/2) | AFK |
| 2. Logowanie magic-link | [#3](https://github.com/CrystalPlatforms/wspolniak-ios/issues/3) | AFK |
| 3. Feed + offline | [#4](https://github.com/CrystalPlatforms/wspolniak-ios/issues/4) | AFK |
| 4. Post: markdown, reakcje, komentarze | [#5](https://github.com/CrystalPlatforms/wspolniak-ios/issues/5) | AFK |
| 5. Lightbox 10× + YouTube | [#6](https://github.com/CrystalPlatforms/wspolniak-ios/issues/6) | AFK |
| 6. Tworzenie posta i upload | [#7](https://github.com/CrystalPlatforms/wspolniak-ios/issues/7) | AFK |
| 7. Albumy | [#8](https://github.com/CrystalPlatforms/wspolniak-ios/issues/8) | AFK |
| 8. Czat WebSocket | [#9](https://github.com/CrystalPlatforms/wspolniak-ios/issues/9) | AFK |
| 9. Push APNs | [#10](https://github.com/CrystalPlatforms/wspolniak-ios/issues/10) | HITL |
| 10. Kalendarz i biblioteka | [#11](https://github.com/CrystalPlatforms/wspolniak-ios/issues/11) | AFK |
| 11. AL — asystent AI | [#12](https://github.com/CrystalPlatforms/wspolniak-ios/issues/12) | AFK |
| 12. iPad adaptacyjny | [#13](https://github.com/CrystalPlatforms/wspolniak-ios/issues/13) | AFK |
| 13. Wydanie unlisted | [#14](https://github.com/CrystalPlatforms/wspolniak-ios/issues/14) | HITL |

---

## Architectural decisions

Durable decisions that apply across all phases:

- **Architektura**: natywny **SwiftUI**, jeden uniwersalny target (iPhone + iPad), iOS 17+,
  lekkie MVVM. Layout adaptacyjny od pierwszej fazy (na iPadzie docelowo sidebar /
  NavigationSplitView — faza 12 to szlif, nie dodawanie od zera).
- **Trzy głębokie moduły** (na nich buduje się reszta aplikacji):
  - **API Client** — jedyna brama do backendu Hono (REST + WebSocket); ukrywa endpointy,
    nagłówki auth, retry i dekodowanie za jednym wąskim interfejsem.
  - **AuthStore** — sesja w Keychain; handshake magic-link przez universal link;
    trwała sesja, wylogowanie, reakcja na cofnięcie dostępu.
  - **PushManager** — rejestracja tokenu APNs w backendzie, prezentacja powiadomień
    i routing (deep link we właściwy ekran).
- **Model danych**: backend = jedyne źródło prawdy, zero duplikacji logiki biznesowej;
  lokalnie tylko cache ostatniego feedu (offline) i sesja.
- **Key entities**: `User`, `Post`, `Media` (zdjęcie lub link YouTube), `Album`,
  `Comment`, `Reaction`, `ChatMessage` (+ mention / reply), `CalendarEvent`,
  `InstanceConfig` (feature toggles), `DeviceToken` (APNs).
- **Auth**: magic link e-mail → universal link na `wspolniak.com` → wymiana na sesję →
  Keychain; działa równolegle z sesją web (to samo konto).
- **Integracje**: istniejący backend Hono (REST + WebSocket) bez zmian w endpointach;
  APNs bezpośrednio (bez OneSignal); YouTube w osadzonym web view; systemowy photo
  picker (HEIC wspierany); endpointy AI po stronie backendu (AL).
- **Dystrybucja**: Unlisted App Store; bundle id `com.crystal.wspolniak`, nazwa
  „Wspólniak", ikona z istniejącego logo; **dwie konfiguracje build**: dev → dev
  instancja, prod → wyłącznie prod instancja.
- **UI**: 100% po polsku (stringi i powiadomienia); design tokens z tożsamości web
  (kolory, logo, typografia).
- **Wydajność (progi z PRD)**: cold start < 2 s (klasa iPhone 12); scroll feedu 60 fps;
  reconnect WebSocket < 3 s; zoom do 10× płynnie; progres uploadu ≤ 500 ms;
  tap w powiadomienie otwiera treść < 2 s.
- **Zależności od backendu** (główne repo `wspolniak`, poza tym repo): Push Hub (APNs
  sender + rejestr tokenów) przed fazą 9; plik `apple-app-site-association` na
  `wspolniak.com` przed fazą 2; endpointy AI przed fazą 11; install banner (story 8)
  — w całości strona web.
- **Weryfikacja**: każda faza kończy się polskim scenariuszem HITL (krok po kroku,
  prawdziwe urządzenia iPhone + iPad, dev instancja) + warstwa automatyczna (XCTest
  przez `xcodebuild test`) + build gates (`xcodebuild build` green dla dev i prod).

---

## Phase 1: Fundament — projekt, design system, API Client, powłoka

**User stories**: 32 (feature toggles), 34 (wariant dev), 35 (wariant prod), 9 (polski UI)

### What to build

Pierwszy pionowy przekrój: projekt Xcode (SwiftUI, uniwersalny iPhone + iPad, iOS 17+,
bundle `com.crystal.wspolniak`, ikona z logo Wspólniaka) z dwiema konfiguracjami build —
dev (dev instancja) i prod (prod instancja). Design tokens (kolory, typografia, odstępy)
z tożsamości web jako jedyny sposób stylowania UI. Szkielet modułu API Client: REST
gateway z dekodowaniem, mapowaniem błędów HTTP i haczykiem na nagłówek autoryzacji.
Powłoka aplikacji: główna nawigacja, polskie stringi, pobranie konfiguracji instancji
i zapamiętanie feature toggles — wyłączone sekcje nie renderują się wcale.

### Assumptions carried in

- Dev instancja jest osiągalna pod znanym bazowym URL-em; endpoint konfiguracji instancji
  istnieje w web API (bez zmian).
- Logo Wspólniaka dostępne jako asset.

### Out of scope for this phase

- Logowanie (faza 2) — powłoka startuje na ekranie placeholder bez auth.
- Jakiekolwiek ekrany treści (feed, albumy, czat) — tylko nawigacja i konfiguracja.
- Push, offline, iPad polish (późniejsze fazy).

### Acceptance criteria

- [ ] Build przechodzi dla konfiguracji dev i prod (destination iPhone i iPad) — [command: `xcodebuild build` green ×2 konfiguracje ×2 destination]
- [ ] API Client dekoduje przykładowe odpowiedzi (konfiguracja instancji, lista postów) i mapuje błędy HTTP na typy aplikacji — [test: XCTest suite dla API Client]
- [ ] Wyłączenie funkcji w konfiguracji instancji (dev) → odpowiadająca sekcja znika z powłoki — [observable: zmiana toggla w dev instancji + restart aplikacji]
- [ ] Apka uruchamia się na symulatorze iPhone i iPad: polskie etykiety, ikona z logo, cold start < 2 s na urządzeniu klasy iPhone 12 — [HITL: scenariusz fazy 1, po polsku]

---

## Phase 2: Autoryzacja magic-link — universal links + Keychain

**User stories**: 3 (magic-link e-mail), 4 (universal link do apki), 5 (trwała sesja), 6 (wylogowanie), 7 (to samo konto co web)

### What to build

Moduł AuthStore: sesja wyłącznie w Keychain. Ekran logowania: wpisanie e-maila →
żądanie magic linka → stan oczekiwania (polskie komunikaty). Obsługa universal linka
na `wspolniak.com`: link z maila otwiera aplikację, następuje wymiana tokenu na sesję
i zapis w Keychain. Przy starcie aplikacji: istniejąca sesja → wejście od razu
zalogowanym; brak → ekran logowania. Wylogowanie z poziomu aplikacji czyści sesję.
Odpowiedź 401 z API → sesja uznana za cofniętą → czyszczenie i ekran logowania.
Wariant dev loguje się do dev instancji, prod — do prod.

### Assumptions carried in

- `apple-app-site-association` serwowane na `wspolniak.com` (backend, główne repo) —
  bez tego faza nie przechodzi walidacji na urządzeniu.
- Endpointy: żądanie magic linka i wymiana tokenu na sesję — istnieją jak dla web.
- Entitlement Associated Domains możliwy do skonfigurowania dla app id.

### Out of scope for this phase

- Brak wielu kont, logowania hasłem, odblokowania biometrycznego.
- Brak treści po zalogowaniu — docelowo wchodzi się w powłokę z fazy 1.

### Acceptance criteria

- [ ] Parsowanie URL-a universal linka (wyjęcie tokenu, odrzucenie obcych linków) — [test: XCTest parsera deep linka]
- [ ] Sesja przetrwa restart aplikacji (zapis → odczyt w nowej instancji store'a); 401 czyści sesję i pokazuje ekran logowania — [test: XCTest persistencji sesji] + [observable: restart i wymuszony 401 na urządzeniu]
- [ ] Pełny scenariusz na urządzeniu: e-mail → link z Maila otwiera apkę zalogowaną; wylogowanie wraca na ekran logowania; to samo konto działa równolegle w web PWA — [HITL: scenariusz fazy 2, po polsku]

---

## Phase 3: Feed — infinite scroll, pull-to-refresh, offline

**User stories**: 10 (nieskończony feed + pull-to-refresh), 16 (polished loading states); decyzja „Offline" z PRD (cache ostatniego feedu)

### What to build

Ekran feedu podpięty do API przez API Client: lista postów (autor, data, podgląd
treści, miniatury mediów, liczniki reakcji i komentarzy), paginacja nieskończona
przy scrollu, pull-to-refresh, placeholdery szkieletowe przy pierwszym ładowaniu,
stany błędu z ponowieniem. Cache ostatniego załadowanego feedu lokalnie — offline
feed renderuje się z cache z dyskretnym oznaczeniem nieświeżości.

### Assumptions carried in

- Auth z fazy 2 działa; żądania idą z nagłówkiem sesji.
- Endpointy feedu bez zmian względem web (paginacja kursorowa jak w web API).

### Out of scope for this phase

- Otwieranie posta (faza 4), upload (faza 6), albumy (faza 7).
- Offline dla innych ekranów niż feed.

### Acceptance criteria

- [ ] Dekodowanie strony feedu z kursorem paginacji + przypadki brzegowe (pusta strona, uszkodzony JSON) — [test: XCTest dekodowania]
- [ ] Scroll dociąga kolejne strony; pull-to-refresh pokazuje świeże posty; skeleton przy pierwszym ładowaniu; błąd sieci → komunikat z „Ponów" — [HITL: scenariusz fazy 3]
- [ ] Tryb samolotowy → feed renderuje się z cache z oznaczeniem offline — [observable: Airplane Mode na urządzeniu]
- [ ] Scroll feedu utrzymuje 60 fps — [observable: Instruments / Time Profiler na urządzeniu]

---

## Phase 4: Post — markdown, @mentions, reakcje, komentarze

**User stories**: 11 (pełna treść z markdown i @mentions), 12 (reakcje bez duplikatów), 13 (komentarze: czytanie i pisanie)

### What to build

Ekran szczegółów posta: pełne renderowanie markdown z wyróżnionymi @mentions,
siatka miniaturek mediów posta (kliknięcie — docelowo lightbox z fazy 5), rząd
reakcji z dodawaniem i przełączaniem własnej reakcji (żadnych duplikatów), lista
komentarzy + kompozytor komentarza (z @mentions). Optymistyczne UI zgodne
z zachowaniem web (toggle reakcji, pojawiający się komentarz).

### Assumptions carried in

- Feed z fazy 3 jako punkt wejścia na szczegóły posta.
- Endpointy reakcji i komentarzy bez zmian względem web.

### Out of scope for this phase

- Lightbox z zoomem i YouTube (faza 5).
- Edycja/usuwanie postów — poza user stories PRD.

### Acceptance criteria

- [ ] Renderer markdown: @mentions, pogrubienia, linki, listy, przypadki brzegowe (pusta treść, zagnieżdżenia) — [test: XCTest renderera na snapshotach tekstu]
- [ ] Logika przełączania reakcji: dodanie własnej, zdjęcie, zmiana — stan bez duplikatów — [test: XCTest logiki reakcji na mock API]
- [ ] Otwórz post: markdown i @mentions wyglądają jak na web; dodaj i zdejmij reakcję; napisz komentarz z @mention (podświetlony); stan zgodny z widokiem web tego samego posta — [HITL: scenariusz fazy 4]

---

## Phase 5: Przeglądarka mediów — lightbox 10× + YouTube

**User stories**: 14 (lightbox z zoomem do 10×), 15 (YouTube w poście bez wychodzenia z apki)

### What to build

Pełnoekranowy lightbox otwierany z mediów posta: pinch zoom do 10×, pan, zoom
dwuklikiem, stronicowanie między mediami posta, gest zamknięcia (przeciągnięcie).
Filmy YouTube z postów renderowane w osadzonym web view — odtwarzanie wewnątrz
aplikacji.

### Assumptions carried in

- Szczegóły posta z fazy 4 przekazują listę mediów.
- Web view z polskim interfejsem systemowym (bez własnego chrome).

### Out of scope for this phase

- Zapisywanie do Zdjęć / pobieranie mediów — poza user stories PRD.
- Galerii albumowych (faza 7 korzysta z tego samego lightboxa).

### Acceptance criteria

- [ ] Zoom osiąga 10× płynnie; pinch, double-tap i pan działają; gest zamknięcia działa — [HITL: scenariusz fazy 5]
- [ ] Filmik YouTube odtwarza się wewnątrz aplikacji, bez przejścia do Safari/YouTube — [HITL: scenariusz fazy 5]
- [ ] Zoom do 10× bez zauważalnych spadków klatek — [observable: Instruments na urządzeniu]

---

## Phase 6: Tworzenie posta i upload zdjęć

**User stories**: 17 (wiele zdjęć, HEIC), 18 (straż nadwymiaru + realne zmniejszanie), 19 (progres per plik + ostrzeżenie o wolnym łączu), 20 (link YouTube jako wideo)

### What to build

Kompozytor nowego posta: systemowy photo picker z wyborem wielu zdjęć (HEIC wspierany),
podglądy załączników. Straż nadwymiaru lustrzana z web: zdjęcie > 19 MB flagowane
przed publikacją — czerwony podgląd z wykrzyknikiem; dialog błędu z opcją „zmniejsz",
która faktycznie redukuje plik i pozwala publikować. Upload z progresem per plik
(odświeżanie ≤ 500 ms) i ostrzeżeniem o wolnym połączeniu. Załączenie linku YouTube
jako wideo. Publikacja → nowy post widoczny w feedzie.

### Assumptions carried in

- Endpointy uploadu bez zmian względem web; próg 19 MB lustrzany z reguł web.
- Feed z fazy 3 pokazuje opublikowany post po odświeżeniu.

### Out of scope for this phase

- Bezpośrednie zdjęcie z aparatu (tylko photo picker) — poza user stories.
- Przypisywanie posta do albumu (faza 7).

### Acceptance criteria

- [ ] Logika strażnika nadwymiaru: próg 19 MB, flagowanie, wynik „zmniejsz" to faktycznie mniejszy plik — [test: XCTest na próbkach danych obrazu]
- [ ] Parsowanie i walidacja linku YouTube → klasyfikacja jako wideo — [test: XCTest parsera]
- [ ] Wybierz wiele zdjęć (w tym duży HEIC) → nadwymiarowe na czerwono z wykrzyknikiem → dialog → zmniejsz → publikuj; progres per plik odświeżany ≤ 500 ms; post widoczny w feedzie — [HITL: scenariusz fazy 6]
- [ ] Ograniczona łączność (Network Link Conditioner) → pojawia się polskie ostrzeżenie o wolnym połączeniu — [HITL: scenariusz fazy 6]
- [ ] Post z linkiem YouTube odtwarza się w lightboxie z fazy 5 — [HITL: scenariusz fazy 6]

---

## Phase 7: Albumy

**User stories**: 21 (przeglądanie albumów jako galeria), 22 (tworzenie i edycja albumów)

### What to build

Ekran listy albumów (okładki, liczby zdjęć), widok albumu jako galerii (siatka,
otwieranie zdjęć w lightboxie z fazy 5), tworzenie albumu i edycja: tytuł,
dodawanie/usuwanie zdjęć. Sekcja respektuje feature toggle instancji.

### Assumptions carried in

- Lightbox z fazy 5 współdzielony.
- Endpointy albumów bez zmian względem web.

### Out of scope for this phase

- Sugestie nazw od AI (faza 11).
- Eksport/udostępnianie albumów poza apką — poza user stories.

### Acceptance criteria

- [ ] Utwórz album, dodaj zdjęcia, zmień tytuł, usuń zdjęcie — stan zgodny z widokiem web tego samego albumu — [HITL: scenariusz fazy 7]
- [ ] Album ukryty przy wyłączonym feature toggle w instancji — [observable: zmiana toggla w dev instancji]
- [ ] Dekodowanie modelu albumu i operacji edycji (mock API) — [test: XCTest]

---

## Phase 8: Czat na żywo — WebSocket

**User stories**: 23 (czat aktualizuje się na żywo), 24 (@mentions i podświetlenia odpowiedzi)

### What to build

Ekran czatu po WebSocket (przez API Client, auth sesją z fazy 2): przychodzące
wiadomości bez odświeżania, wysyłanie wiadomości, @mentions z wyróżnieniem,
odpowiedzi (reply) z wizualnym podświetleniem i przewinięciem do cytowanej
wiadomości, stan nieprzeczytanych. Automatyczny reconnect po zerwaniu połączenia
w < 3 s.

### Assumptions carried in

- Protokół i endpoint WebSocket bez zmian względem web.
- Sesja z fazy 2 uwierzytelnia połączenie WS.

### Out of scope for this phase

- Push dla czatu (faza 9).
- Wskaźniki pisania / przeczytania — poza user stories PRD.

### Acceptance criteria

- [ ] Parsowanie wiadomości i zdarzeń WS (mention, reply) — [test: XCTest na przykładowych ramkach]
- [ ] Reconnect < 3 s po zerwaniu połączenia — [observable: przełączenie Wi-Fi / Network Link Conditioner + stoper]
- [ ] Dwa urządzenia: wiadomość pojawia się natychmiast bez odświeżania; @mention podświetlony; odpowiedź podświetlona z przewinięciem do źródła — [HITL: scenariusz fazy 8]

---

## Phase 9: Powiadomienia push — APNs

**User stories**: 29 (push dla tych samych zdarzeń co web), 30 (polskie treści powiadomień), 31 (tap otwiera właściwą treść)

### What to build

Moduł PushManager: żądanie zgody, rejestracja tokenu APNs w backendzie (rejestr
tokenów urządzeń), obsługa otrzymanych powiadomień z polską prezentacją, tap →
deep link otwierający właściwy ekran (post / komentarz / wiadomość czatu) — także
z aplikacji zamkniętej. Parsowanie deep linków współdzielone z universal linkami
(faza 2). Brak zgody = aplikacja działa normalnie.

### Assumptions carried in

- **Backendowy Push Hub (APNs sender + rejestr tokenów) wdrożony w głównym repo** —
  twarda zależność z PRD; bez niego faza nie przechodzi walidacji.
- Klucz APNs i capability skonfigurowane na koncie deweloperskim.
- Zbiór zdarzeń = obecne triggery web push (definiowane po stronie backendu).

### Out of scope for this phase

- Ekran ustawień powiadomień w aplikacji — poza user stories.
- Android (osobne repo).

### Acceptance criteria

- [ ] Parsowanie deep linka z payloadu powiadomienia → ścieżka ekranu dla każdego typu zdarzenia — [test: XCTest parsera (rozszerzenie testów z fazy 2)]
- [ ] Po nadaniu zgody token urządzenia widoczny w rejestrze backendu — [observable: rejestr tokenów w backendzie dev]
- [ ] Zamknięta apka → wyzwolone zdarzenie (np. nowy komentarz) → powiadomienie po polsku → tap otwiera właściwą treść < 2 s — [HITL: scenariusz fazy 9]
- [ ] Odmowa zgody na powiadomienia → aplikacja działa normalnie, bez błędów — [HITL: scenariusz fazy 9]

---

## Phase 10: Kalendarz i biblioteka mediów

**User stories**: 25 (przeglądanie kalendarza rodzinnego), 26 (przeglądanie biblioteki mediów)

### What to build

Ekran kalendarza (przeglądanie wydarzeń rodziny, zgodnie z widokiem web) i ekran
biblioteki mediów (siatka wszystkich kiedykolwiek udostępnionych zdjęć, paginacja,
otwieranie w lightboxie). Oba za feature toggles, ze spójnymi stanami ładowania
i polskim UI.

### Assumptions carried in

- Endpointy kalendarza i biblioteki bez zmian względem web.
- Lightbox współdzielony z fazą 5.

### Out of scope for this phase

- Tworzenie wydarzeń (panel admina = web only).
- Filtry/wyszukiwanie wykraczające poza paritet z web.

### Acceptance criteria

- [ ] Kalendarz: przewijanie wydarzeń zgodnie z web; biblioteka: siatka, paginacja, otwarcie zdjęcia w lightboxie — [HITL: scenariusz fazy 10]
- [ ] Obie sekcje znikają przy wyłączonych odpowiednich toggles — [observable: zmiana konfiguracji instancji dev]
- [ ] Dekodowanie modeli wydarzeń i biblioteki — [test: XCTest]

---

## Phase 11: AL — asystent AI

**User stories**: 27 (AI-opis zdjęcia do wykorzystania w poście), 28 (AI-sugestie nazw albumów)

### What to build

W kompozytorze: generowanie opisu AI dla załączonego zdjęcia → opis wpada do pola
treści posta (edytowalny przed publikacją). W edytorze albumu: AI-sugestie nazw
albumów → wybór ustawia tytuł. Wywołania przez endpointy backendowe (te same co web);
błędy AI obsługiwane czytelnym polskim komunikatem bez blokowania kompozytora.

### Assumptions carried in

- Endpointy AI dostępne po stronie backendu (jak dla web) — twarda zależność.
- Kompozytor (faza 6) i edytor albumu (faza 7) istnieją.

### Out of scope for this phase

- Jakiekolwiek modele on-device, generowanie obrazów — poza PRD.

### Acceptance criteria

- [ ] Wygeneruj opis zdjęcia → opis widoczny w polu posta, edytowalny, publikowalny — [HITL: scenariusz fazy 11]
- [ ] Sugestie nazw albumów → wybór sugestii ustawia tytuł albumu — [HITL: scenariusz fazy 11]
- [ ] Błąd endpointu AI → polski komunikat, kompozytor/edytor nadal w pełni działa — [observable: wymuszenie błędu na dev instancji]

---

## Phase 12: iPad — adaptacyjny layout

**User stories**: 33 (sidebar, dwukolumnowa treść), 16 (dokończenie szlifu stanów ładowania)

### What to build

Przejście całej aplikacji na layout adaptacyjny na iPadzie: sidebar / NavigationSplitView
dla głównych sekcji, dwukolumnowy widok tam, gdzie ma sens (np. feed + szczegóły),
obsługa klas rozmiarów, rotacje i Split View. Przegląd stanów ładowania na wszystkich
ekranach. iPhone bez regresji.

### Assumptions carried in

- Wszystkie ekrany istnieją (fazy 3–11); nawigacja budowana adaptacyjnie od fazy 1.
- Lightbox, czat i upload działają na obu klasach rozmiarów.

### Out of scope for this phase

- Widgety, wiele okien, watchOS — poza zakresem PRD.

### Acceptance criteria

- [ ] Na iPadzie: sidebar z nawigacją, dwukolumnowe treści gdzie przewidziane, wszystkie ekrany działają w rotacji i Split View — [HITL: scenariusz fazy 12 na iPadzie]
- [ ] iPhone: brak regresji układu względem wcześniejszych faz — [HITL: scenariusz regresyjny na iPhonie]
- [ ] Build green dla destination iPhone i iPad — [command: `xcodebuild build` ×2 destination]

---

## Phase 13: Wydanie — Unlisted App Store

**User stories**: 1 (instalacja z linku zaproszenia), 2 (apka trwała i aktualizowana automatycznie), 34/35 (walidacja wariantów dev/prod); story 8 (install banner) — wyłącznie po stronie web w głównym repo

### What to build

Walidacja wariantu prod (łączy się wyłącznie z prod instancją), build archiwum
i materiały do wniosku o unlisted distribution, instalacja na urządzeniach rodziny
przez bezpośredni link zaproszenia, weryfikacja trwałości apki i automatycznych
aktualizacji. Komplet polskich scenariuszy HITL dla rodziny zapisany w repo.
Aktualizacja README (status: released).

### Assumptions carried in

- Apple Developer Program aktywne; wniosek o unlisted distribution złożony
  i zatwierdzony przez Apple (założenie z PRD).
- Wszystkie funkcje ukończone w fazach 1–12; backend (Push Hub, AASA) działa na prod.

### Out of scope for this phase

- Publiczna lista w App Store, Android, watchOS/widgets — poza zakresem PRD.
- Zmiany w web PWA (banner instalacji = główne repo).

### Acceptance criteria

- [ ] Archiwum konfiguracji prod buduje się; build prod łączy się wyłącznie z prod instancją (brak danych testowych) — [command: `xcodebuild archive` prod] + [observable: ruch/zawartość na prod vs dev]
- [ ] Link zaproszenia instaluje apkę na rodzinnym iPhonie i iPadzie; apka działa bez rebuildu dłużej niż 90 dni — [observable: instalacja przez link + obserwacja w czasie]
- [ ] Komplet polskich scenariuszy HITL dla rodziny zapisany w repo — [observable: katalog scenariuszy w repo]
- [ ] Po wydaniu nowej wersji apka zaktualizowała się automatycznie na urządzeniu rodzinnym — [observable: obserwacja po publikacji aktualizacji]
