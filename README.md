# Flare

Emergency help that works anywhere, even offline. A native SwiftUI iOS app.

Flare uses the phone's location to work out the country (or state) you are in and shows the emergency numbers for it, from an emergency-number database stored inside the app. See the design overview for the look: night navy background, flare orange reserved for the call action, Archivo type.

## Open and run

1. Open `Flare.xcodeproj` in Xcode 16 or later (the project uses file-system-synchronized folders).
2. Select the **Flare** target, then **Signing & Capabilities**: choose your Team and change the bundle identifier from `com.example.Flare` to your own.
3. Run on an iPhone or an iPhone simulator (iOS 17+). In the simulator, set a location with **Features → Location**.

The project has no third-party dependencies. It was written outside Xcode, so the first build may report small issues to fix.

## What is built (first milestone)

| Area | Status |
| --- | --- |
| **Home** | Header with location and "Offline ready" pill, call area that adapts to the country, Nearby and Tools tiles (shown as "Coming soon"), floating tab bar |
| **Location** | Core Location, one approximate fix at launch and on returning to the app; reverse geocoding to country, US state or listed city; manual country/state/city picker |
| **Offline data** | `Flare/Resources/emergency.sqlite` is bundled, validated at startup, copied to Application Support and opened read-only |
| Nearby, Map, Numbers, Medical ID, Battery saver, Fall detection, SMS / Satellite | Designed, **not built yet**. Their tiles and tabs say "Coming soon" instead of showing fake data |

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
  Screens/                 Home, call area, numbers, picker, data info, tabs
  Resources/               emergency.sqlite, Archivo fonts (SIL OFL)
  Assets.xcassets/         app icon, accent and launch colors
```

## Next

Nearby map and services, Numbers directory, Medical ID, battery saver mode, fall detection (Core Motion, with confirmation), SMS and satellite guidance, onboarding and location permission screens, settings. Check the App Store and trademark records before the name Flare is final.
