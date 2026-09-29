# Kist Book

Installment (qist) management app for shops — built for **Alif Electronics**-style
businesses that sell mobiles/electronics on monthly installments.

## What v1 does

- **Login**: mobile number OTP ya email se. Ek number/email par sirf ek hi
  account. Login ke baghair app nahi khulti.
- **Customer list** with key fields up front: name, cell/WhatsApp, monthly
  installment, current due, balance + status dot (green/yellow/red).
  One tap to call, one tap to open WhatsApp with a pre-filled reminder.
  Each customer has a **separate full file**: account, customer info,
  product & plan, **guarantors**, and collection history.
- **Outstanding screen (home)**: app kholte hi sirf pending customers —
  naam, installment amount, due, balance samne. Har row pe **call + WhatsApp
  buttons**. Naam pe tap → poori file. Har import ke baad "Last updated" time
  show hota hai taake bharosa rahe data fresh hai.
- **Customer ki poori file print jesi**: Account Information, Customer
  Information, Officers, Product & Plan, Collection history — aur har
  **guarantor ke sath call + WhatsApp buttons** (dono guarantors ke).
- **Import from your existing prints** (the two formats you already use),
  har format ke liye **3 asaan tareeqe**:
  1. **Scan karo (camera)** — ek ya zyada pages, ek ke baad ek scan, phir
     "Bas, pages parho" dabao. App khud parh kar data update kar degi.
  2. **Gallery se photos** — pehle se li hui tasveeren.
  3. **PDF file** — multiple customers wali PDF upload karo.
  4. **Manual likhen (aakhri option)** — agar scan/PDF na ho sake to haath
     se entry: A/C No. se record match karke update/create.
  Tarteeb: pehle PDF, phir scan, phir gallery, aakhir me manual.
  Phir **review screen** (confirm se pehle sab check karo), phir save —
  data **foran update** + cloud sync. Jo naam nayi outstanding me nahi,
  woh auto **clear** (toggle se on/off).
- **Review-before-save**: every import shows parsed rows for confirmation
  before anything is written.
- **Dashboard**: total outstanding, total due this month, cleared count,
  per-officer breakdown.
- **Reminders**: SMS directly from the phone + one-tap WhatsApp
  (`wa.me` with pre-filled Urdu/English message). Fully automatic WhatsApp
  sending is intentionally NOT included — it violates WhatsApp's terms and
  gets numbers banned.

## Project layout

```
lib/
  main.dart                  App entry + bottom navigation
  models/customer.dart       Customer, Guarantor, CollectionEntry, parse helpers
  services/parsers.dart      Pure parsing logic for both print formats
  services/customer_store.dart ChangeNotifier store + sqflite persistence
  services/reminders.dart     SMS + WhatsApp reminder sending
  screens/customer_list_screen.dart
  screens/customer_detail_screen.dart   (separate file per customer incl. guarantors)
  screens/outstanding_screen.dart       (pending-only list + instant payment entry)
  screens/import_screen.dart  Scan / PDF upload → OCR → review → save
  screens/dashboard_screen.dart
tool/
  validate_parser.py         Standalone check of the outstanding-row parser
                             against real rows from your print (run with python3)
```

## How to run

1. Install the Flutter SDK (>=3.2): https://docs.flutter.dev/get-started/install
2. `cd kistbook`
3. `flutter pub get`
4. Connect an Android phone (or start an emulator)
5. `flutter run`

> Note: `telephony` (direct SMS) is Android-only. On iOS the app falls back
> to opening the SMS app with a pre-filled message.

## Firebase setup (login + cloud sync)

1. [console.firebase.google.com](https://console.firebase.google.com) par
   naya project banayen: `kistbook`.
2. `kistbook` folder ke andar `flutter create .` chalaye — `android/` aur
   `ios/` folders ban jayenge.
3. Firebase console → Project settings → **Add app → Android**.
   Package name `android/app/build.gradle` se len (default
   `com.example.kistbook`, apne naam par badal len).
   `google-services.json` download karke `android/app/` me rakhen.
   (iOS ke liye `GoogleService-Info.plist` → `ios/Runner/`.)
4. **Authentication → Sign-in method**: `Phone` aur `Email/Password` enable
   karen.
5. Phone OTP ke liye apne debug/release **SHA-1 fingerprint** project
   settings me add karen:
   `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
6. **Firestore Database → Create database** (production mode), phir is
   project ki `firestore.rules` deploy karen:
   `firebase deploy --only firestore:rules`
7. `flutter pub get` → `flutter run`.

## Security & privacy design

- **Login**: mobile number OTP ya email/password. Ek number/email par
  **sirf ek hi account** banta hai — ye Firebase Auth khud enforce karta hai.
- **Personal data**: har user ka data `/users/{uid}/...` me hai aur sirf wohi
  user dekh sakta hai (`firestore.rules` me owner-only access). Koi doosra
  user, staff ya bahar wala isay nahi dekh sakta.
- **Read-only jahan zaroori**: paiso ka hisaab (installment, balance, due,
  paid) sirf **import** se update hota hai — A/C No. se match karke. Koi
  haath se rakam nahi badal sakta.
- **Editable jahan zaroori**: customer ke **contact numbers** (Cell/Tel),
  **additional contacts** (jitne marzi numbers add/edit/delete, har ek pe
  call + WhatsApp), aur **Notes/Remarks** tum khud kabhi bhi badal sakte ho.
  Har change foran save + cloud sync hota hai.
- **Import history**: har upload ka log (kitne update, kitne naye, kitne
  clear) cloud me save hota hai.
- **Offline + online, Udhar Book ki tarah**: poori app bina internet ke
  chalti hai (local database, on-device OCR scan). Internet mile to data
  khud sync ho jata hai — kuch dabane ki zaroorat nahi.
- **Social packages par bhi**: WhatsApp reminders WhatsApp app ke through
  jate hain (jo social bundles me free hota hai). Dashboard me **"Sync sirf
  WiFi par"** ka option hai taake mobile data na lage.

## Parser notes

`services/parsers.dart` contains only pure functions (no Flutter imports), so
the logic is unit-testable. `tool/validate_parser.py` mirrors the
outstanding-row parser in Python and was validated against real rows
transcribed from your outstanding print.

The v1 row parser is **anchor-based**:
- `03XXXXXXXXX` (cell number) splits each row into left/right halves
- left: `Sr# A/CNo AccDate … name … officer`
- right: `ITEM PRICE BALANCE INSTALLMENT OS PAID CURRENT_DUE LAST_DATE`

Upgrade path: use ML Kit `TextLine.boundingBox` x-positions to slice columns
instead of regex — the `OcrLine` class already carries coordinates for this.

## Roadmap (not in v1)

- Firebase sync (multi-device, owner + staff)
- PDF statement import via `pdf_render` (scaffolded in import_screen.dart)
- Urdu OCR model check, payment receipt printing, staff roles
