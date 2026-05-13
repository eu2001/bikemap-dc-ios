<h1 align="center">
  <img src=".github/images/logo.png" width="120" alt="BikeMap DC logo"><br>
  BikeMap DC — iOS
</h1>

<p align="center">
  <strong>The DC Collaborative Bike Map.</strong><br>
  A community-curated cycling map for the Washington, D.C. metro area.
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#stack">Stack</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#data-sources">Data sources</a> ·
  <a href="#license">License</a>
</p>

---

BikeMap DC pulls together everything a cyclist needs in DC — protected bike
lanes, Capital Bikeshare stations, fix-it stands, bike shops, water fountains,
public transit, four years of crash data, and live community contributions —
into one fast, ad-free iOS app.

## Features

- 🗺️ **Full coverage map** of DC, Arlington, Alexandria, Falls Church, Tysons,
  Bethesda, Silver Spring, Capitol Heights, College Park, Hyattsville, New
  Carrollton, and Suitland.
- 🚴 **5,500+ bike-infrastructure segments** — 9 categories matching the
  goDCgo legend (protected, conventional, contraflow, bus/bike, shared/sharrow,
  signed route, off-street trail, unpaved trail, mountain bike).
- 📍 **5,700+ points of interest** — bike parking, Capital Bikeshare,
  fix-it stands, bike shops, water fountains, public restrooms, Metro,
  commuter rail, rec centers, landmarks.
- 💥 **1,700+ cyclist crash locations** from the past 4 years of DC Vision
  Zero data.
- ➕ **Add your own points** — Bike Parking / Fix-it Stand / Bike Shop /
  Bikeshare / Water Fill / Restroom — with a draggable mini-map pin.
- 🚨 **Report bike thefts** with optional photo and community push
  notifications.
- ⚠️ **Report cyclist accidents** to surface safety concerns on the map.
- 🔒 **Bike registry** — keep nickname, brand, color, serial number, photo,
  and details for every bike you own (with Conventional / E-bike toggle).
- 👮 **Admin moderation panel** — review pending submissions, fix titles or
  pin locations before approving, delete misplaced markers.
- 🌐 **English + Latin American Spanish** localization, switchable in-app.
- 📍 **Live user-location** dot with accuracy halo (5 m precision).
- 🛡️ **5-mile contribution gate** — points can only be added from within DC.

## Screenshots

<p align="center">
  <img src=".github/images/welcome.png" width="280" alt="Sign in screen">
</p>

## Stack

- **SwiftUI** + **MapKit**
- **Supabase** (Auth · Postgres · Storage · Edge Functions)
- **URLSession** for the Overpass / DDOT / DCGIS data importers
- Backed by ~10 Supabase Edge Functions (TypeScript / Deno):
  `register-user`, `import-dc-infra`, `import-dc-amenities`,
  `import-dc-crashes`, `import-dc-extras`, `bulk-upsert-pois`,
  `bulk-upsert-infra`, `notify-admin-furto`, `notify-users-furto`,
  `notify-admins-new-poi`, `delete-account`.

## Getting started

```bash
git clone git@github.com:eu2001/bikemap-dc-ios.git
cd bikemap-dc-ios
open BikeMapDC.xcodeproj
```

Then in Xcode:

1. Select **BikeMapDC** scheme.
2. Pick an iOS 17+ simulator or device.
3. **Run** (`⌘R`).

Bundle ID is `com.bikemap.dc`. To run on a device you'll need your own Apple
developer account and a fresh provisioning profile.

The app talks to a live Supabase project at
`hobulqkujiczaakaucwz.supabase.co` using the public anon key embedded in
`SupabaseClient.swift`. Row-level security policies enforce all access rules.

## Data sources

| Source | Used for |
|---|---|
| [DDOT — District Department of Transportation](https://opendata.dc.gov/) | Bike lanes, bike parking, Capital Bikeshare station registry |
| [DCGIS](https://maps2.dcgis.dc.gov/dcgis/rest/services/DCGIS_DATA) | Metro stations, MARC/VRE stops, signed routes, rec centers |
| [Capital Bikeshare GBFS](https://gbfs.capitalbikeshare.com/gbfs/gbfs.json) | Live station roster |
| [WMATA](https://www.wmata.com/schedules/maps/) | Metrorail roster cross-reference |
| [MPD Vision Zero](https://opendata.dc.gov/datasets/DCGIS::crashes-in-dc) | Cyclist injury / fatality crashes |
| [OpenStreetMap](https://www.openstreetmap.org/copyright) | Bike shops, fix-it stands, water fountains, trailheads, MTB trails, bus/bike lanes |
| [goDCgo](https://godcgo.com) | Map legend & coverage area reference |

All imported data is attributed to its original source on every row.

## Companion projects

- **Android** sibling: [`bikemap-dc-android`](https://github.com/eu2001/bikemap-dc-android) — same backend, Flutter UI
- **Support & user guide**: https://sites.google.com/view/bikemapdc
- **Privacy policy**: https://sites.google.com/view/bikemapdc/privacy

## Contributing

PRs welcome for bug fixes, accessibility, and translations. For data
corrections (a missing fix-it stand, a closed bike shop, etc.) email
**bikemap.dc@gmail.com** with the point's reference code — every point in the
app shows its code in the title (e.g. `BP4231` for Bike Parking #4231).

## License

[MIT](LICENSE) — do what you want with the code; please don't blame us if
something goes wrong.

The imported map data remains under the licenses of its original sources
(DDOT, DCGIS, OpenStreetMap ODbL, etc.).
