# Flare

Emergency help that works anywhere, even offline. A native SwiftUI iOS app.

Flare uses the phone's location to work out the country (or state) you are in and shows the emergency numbers for it, from an emergency-number database stored inside the app. See the design overview for the look: night navy background, flare orange reserved for the call action, Archivo type.

## Open and run

1. Open `Flare.xcodeproj` in Xcode 16 or later (the project uses file-system-synchronized folders).
2. Select the **Flare** target, then **Signing & Capabilities**: choose your Team and change the bundle identifier from `com.example.Flare` to your own.
3. Run on an iPhone or an iPhone simulator (iOS 17+). In the simulator, set a location with **Features → Location**.

The project has no third-party dependencies. It was written outside Xcode, so the first build may report small issues to fix.

## What is built

| Area | Status |
| --- | --- |
| **Home** | Header with location and "Offline ready" pill, call area that adapts to the country, Nearby and Tools tiles (shown as "Coming soon"), floating tab bar |
| **Location** | Core Location, one approximate fix at launch and on returning to the app; reverse geocoding to country, US state or listed city; manual country/state/city picker |
| **Offline data** | `Flare/Resources/emergency.sqlite` is bundled, validated at startup, copied to Application Support and opened read-only |
| **Numbers** | Every number that applies at the selected location (including the country or state above it), grouped by what it is for, with search, coverage, notes, hours and last-confirmed date. "Look up another country" browses any area offline without changing your location |
| **Medical ID** | Name, date of birth, blood type, allergies, conditions, medications, organ donor status, notes and up to 5 emergency contacts with one-tap Call and Message. Everything is optional |
| **Nearby (Map tab)** | Live search of hospitals, police stations, fire stations and pharmacies through Apple Maps (MapKit), shown on a map and as a list with Directions and Call. Results are saved on the phone, so with no connection Flare shows places saved from earlier searches (within 100 km). A **Compass** view points to the nearest one using only GPS and the compass: no map tiles, no signal |
| **Emergency Mode** | One dark, low-power screen (Home > Tools, or the Shortcuts / Siri / Action Button action "Start Emergency Mode"): the local emergency number buttons, GPS coordinates with a Plus Code, "Text my location to my emergency contacts", contact call buttons, Medical ID summary, battery guard and a "No signal?" card with satellite guidance |
| Fall detection | Designed, **not built yet**. Its tile says "Coming soon" instead of showing fake data |

## How the call area decides what to show

Only the call area changes with the country. Numbers are grouped by the number itself, so nothing is guessed:

- One number for the area: the large round CALL button (for example 911).
- Several numbers: one button per number, titled by the services that use it (for example Japan: 119 "Fire · Ambulance", 110 "Police", 118 "Rescue").
- More than five numbers: the first five, plus "Show N more numbers".
- Police, fire or ambulance with no verified number (and no all-emergencies number): a note says so.
- No verified number at all (for example Canada in this release): the screen says so and points to the phone's built-in emergency call. **No number is ever invented or borrowed from another country.**
- "All numbers and details" lists every number (including poison and crisis lines, SMS and web contacts) with the area it covers, notes, hours (unknown shows "Hours not confirmed", never 24/7) and the date it was last confirmed.

Calls start only when the person taps a button (`tel:`); nothing dials automatically.

## Offline behavior

- The numbers always work offline.
- Finding your country from your location uses Apple's reverse geocoding, which needs a connection. Offline, Flare keeps the last place it confirmed. If the phone is more than about 100 km from that place, it shows a notice asking you to check the location.
- A manual choice is kept until you tap "Use my location".

## Nearby: how it works and its limits

- Searching sends the approximate location to Apple Maps. The location permission text says so. Flare has no servers of its own.
- Flare only searches after the person has opened the Nearby tab once; after that it refreshes quietly when the phone moves more than 1 km or after 10 minutes, so saved places stay fresh.
- Saved places live in `Application Support/Flare/nearby-cache.json` (complete file protection, excluded from backups, at most 600 places, dropped after 90 days). They reveal roughly where the person has been, so the tab shows a count and a "Delete saved places" button.
- Offline, only places near somewhere the person has already searched are available. A place that has never been searched has no data. Bundling an offline OpenStreetMap facility database would remove that limit (a later option).
- Compass direction is a straight line, not a route. The screen says so, warns when the location is approximate, and works without a compass (it then says the direction in words).
- Results are not verified by Flare. A listed hospital may have no emergency department, and a place's phone number is not an emergency number. The screen says both.

## Emergency Mode: how it works and its limits

- **Battery guard steps by itself:** Normal, then Saving power at 30% or whenever Low Power Mode is on, then Critical at 10%. Saving power lowers brightness to at most 50% and slows GPS. Critical lowers it to at most 30%, drops the Medical ID card and keeps the call buttons, coordinates, text-my-location and contacts. Flare only ever lowers brightness (never raises it) and puts it back when the screen closes or Flare leaves the foreground. While charging, the steps follow Low Power Mode only.
- **Time left** is an estimate from how fast the battery dropped since the screen opened (needs about 5 minutes and a 1% drop). iOS gives apps no such number, so the screen says it is rough.
- **What iOS does not allow, and the app says so:** apps can't pause other apps, turn on Low Power Mode, Airplane Mode or radios, show other apps' battery use, or make the phone open an app when it is unlocked. Emergency Mode shows a checklist for what the person must do, and the "Make Emergency Mode one tap" guide explains a Shortcuts shortcut (Set Low Power Mode, then Start Emergency Mode), the Action Button / Back Tap, and Guided Access. The guide's setup steps depend on iPhone model and iOS version and should be tried before they are needed. If Flare is on screen when the phone locks, iOS returns to it on unlock.
- **Text my location** opens the system Messages composer with the person's emergency contacts from Medical ID, coordinates, an Apple Maps link and a Plus Code. iOS does not let an app send a text silently, so the person taps Send. Where Messages can't send (for example the simulator) it offers the share sheet.
- **Satellite:** Flare can't use satellite. The card only points to the iPhone's own Emergency SOS via satellite on models and in countries that support it.
- Coordinates come from GPS, run only while the screen is open, and never leave the phone. Plus Code encoding follows the Open Location Code standard (checked against its published example).

## Medical ID storage and limits

- Saved as one JSON file (`Application Support/Flare/medical-id.json`) with iOS complete file protection, so it is encrypted whenever the phone is locked. No network code touches it.
- Flare can only show it once the phone is unlocked. The screen tells the person to also set up Medical ID in the Health app for lock-screen access. Flare does not read or write HealthKit.
- If a saved file can't be read, it is never overwritten silently: "Try again" re-reads it, and "Start new" keeps the unreadable file (renamed) before saving.
- Phone numbers must contain only digits, spaces, dashes, brackets and a leading +, so a call is never started from a guessed number.

## Data

`Flare/Resources/emergency.sqlite` is release **2026.10.10.2** from the `database` folder (670 contacts, 179 countries and areas, all US states and DC), checksum-matched to `database/emergency.sqlite.sha256`.

`Flare/Data/EmergencyDatabase.swift` is adapted from `database/ios/EmergencyDatabase.swift`. Changes: typed lookup, area and metadata queries, recovery from a bad working copy (previous, then bundled), a newer bundled database replaces an older working copy, and the future-date clock check was removed so a phone with a wrong clock can't lock the app out of its numbers.

To ship a newer database, replace `Flare/Resources/emergency.sqlite`; the app picks it up on next launch when its `published_at` is newer.

**Before any public release:** the data includes facts derived from ITU-T E.129. The database's own `docs/attribution.md` says ITU's terms don't establish onward-distribution rights and that permission should be resolved before external redistribution. The numbers were reviewed with AI assistance and have not been test-called. The app's "About this data" sheet says both.

## Layout

```
Flare.xcodeproj
Config/Info.plist          location text, launch color, dark style
Flare/
  FlareApp.swift
  Design/                  colors, Archivo type, components
  Data/                    models, SQLite actor, call planner, dialing, bundle lookup
  Location/                Core Location + reverse geocoding
  Store/                   EmergencyStore (database + selection + call plan)
  MedicalID/               model, file store, Medical ID screen and editor
  Nearby/                  place models, live search store, saved-places cache, compass
  EmergencyMode/           Emergency Mode screen, battery monitor, GPS, Plus Code, text-location, Shortcuts action
  Screens/                 Home, call area, Numbers, picker, data info, tabs
  Resources/               emergency.sqlite, Archivo fonts (SIL OFL)
  Assets.xcassets/         app icon, accent and launch colors
```

## Next

Fall detection (Core Motion, with confirmation), SMS and satellite guidance, onboarding and location permission screens, settings. Check the App Store and trademark records before the name Flare is final.
