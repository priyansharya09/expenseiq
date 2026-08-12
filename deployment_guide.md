# 🚀 ExpenseIQ — Deployment & APK Release Guide

## Your Questions Answered

| Question | Short Answer |
|---|---|
| Multi-user with data on any device? | Deploy your Django backend to a **cloud server** — each user's data lives server-side and follows them across devices |
| Data backup? | Use **PostgreSQL** on the cloud (auto-backed up) instead of local SQLite |
| Can't test Splits? | The Split feature needs **Contacts** created first — walkthrough below |
| How to release APK? | `flutter build apk --release` after pointing to the cloud URL |

---

## The Core Problem

Right now your architecture looks like this:

```
Phone → API calls → localhost:8000 (your PC)
```

This only works while your PC server is running **and** the phone is on the same Wi-Fi. For a real release, you need:

```
Any Phone → API calls → https://your-app.railway.app (cloud server)
                              ↓
                         PostgreSQL (cloud DB)
```

---

## Step 1: Deploy the Backend to a Cloud Server

You have several **free/cheap** options. Here are the two easiest:

### Option A: Railway (Recommended — Easiest)

> [!TIP]
> Railway gives you $5/month free credit — more than enough for a personal app.

1. **Create account** at [railway.app](https://railway.app)

2. **Add a PostgreSQL database**:
   - Click **"New Project"** → **"Provision PostgreSQL"**
   - Copy the `DATABASE_URL` (looks like `postgresql://user:pass@host:port/dbname`)

3. **Prepare your backend for Railway**. Create these files:

**`d:\expenseiq\expenseiq\backend\Procfile`**:
```
web: cd expenseiq && gunicorn expenseiq.wsgi --bind 0.0.0.0:$PORT
```

**`d:\expenseiq\expenseiq\backend\runtime.txt`**:
```
python-3.11.9
```

4. **Update settings.py for production**:

```python
# In settings.py, replace the DATABASES block:
import dj_database_url

DATABASES = {
    'default': dj_database_url.config(
        default='sqlite:///db.sqlite3',
        conn_max_age=600,
    )
}

# Add whitenoise for static files
MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',  # Add this
    # ... rest stays the same
]

STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
```

5. **Add to requirements.txt**:
```
dj-database-url==2.1.0
whitenoise==6.6.0
```

6. **Deploy via Railway CLI or GitHub**:
```bash
# Install Railway CLI
npm install -g @railway/cli

# Login & deploy
railway login
railway init
railway up
```

7. **Set environment variables on Railway**:
```
DJANGO_SECRET_KEY=some-random-50-char-string
DEBUG=False
ALLOWED_HOSTS=your-app.railway.app
DATABASE_URL=<auto-set by Railway>
```

8. **Run migrations on Railway**:
```bash
railway run python expenseiq/manage.py migrate
```

### Option B: Render (Also Free Tier)

Similar process — Render has a free PostgreSQL that sleeps after 90 days but works well for testing.

### Option C: Your Own VPS (DigitalOcean/AWS)

More control but requires Linux server management. ~$5/month.

---

## Step 2: Update Flutter App to Use Cloud URL

Once your backend is deployed (say at `https://expenseiq-backend.railway.app`), update the API service:

```dart
// In api_service.dart, change the baseUrl getter:

static String get baseUrl {
  // Production cloud URL
  const cloudUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://expenseiq-backend.railway.app/api',
  );

  if (kIsWeb) {
    return cloudUrl;
  }

  // For local development, override with API_HOST
  if (_envApiHost.isNotEmpty) {
    return 'http://$_envApiHost:8000/api';
  }

  return cloudUrl;
}
```

This way:
- **Release APK** → always hits the cloud server
- **Local dev** → you can still pass `--dart-define=API_HOST=192.168.x.x` for testing

---

## Step 3: Multi-User Already Works! ✅

Your app **already has multi-user support** built in:

- ✅ Django JWT authentication (login/register)
- ✅ Each user's transactions are filtered by `user` in the backend
- ✅ Tokens stored securely on device

Once the backend is on a cloud server:
- **User A** registers on Phone 1 → data saved to cloud DB
- **User A** logs in on Phone 2 → sees all their expenses
- **User B** registers → has completely separate data

> [!IMPORTANT]
> The only thing you need is the backend running on a public URL instead of localhost!

---

## Step 4: Testing the Splits Feature

The Splits feature requires **Contacts** to be set up first. Here's how to test it:

### Quick Test Steps:

1. **Go to Splits tab** (bottom nav bar)
2. **Tap the "+" button** → choose "Add Split"
3. **You'll first need to create a Contact**:
   - The screen should have an option to add a contact
   - Enter a name (e.g., "Rahul") and phone/email
4. **Create a Debt record**:
   - Select the contact
   - Choose "Lend" or "Borrow"
   - Enter amount and description
5. **View the split** in the Splits tab
6. **Settle** by tapping on the debt card

### If Contacts aren't loading, test the API directly:

```bash
# Create a contact via API (from your terminal)
curl -X POST http://localhost:8000/api/contacts/ \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Friend", "phone": "9876543210"}'

# Create a debt
curl -X POST http://localhost:8000/api/debts/ \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"contact": 1, "amount": "500.00", "type": "lend", "description": "Lunch"}'
```

---

## Step 5: Build the Release APK

### Prerequisites:

1. **Update app identity** in `android/app/build.gradle.kts`:
```kotlin
defaultConfig {
    applicationId = "com.yourdomain.expenseiq"  // Change this!
    minSdk = 21  // or flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

2. **Update app name** in `AndroidManifest.xml`:
```xml
<application
    android:label="ExpenseIQ"  <!-- Change from "flutter_app" -->
```

### Create a Signing Key (one-time):

```powershell
# Run this in PowerShell
keytool -genkey -v -keystore d:\expenseiq\expenseiq\flutter_app\android\app\upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

> [!CAUTION]
> **Save this keystore file and password safely!** You cannot update the app on Play Store without it.

### Create key.properties:

Create `d:\expenseiq\expenseiq\flutter_app\android\key.properties`:
```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=app/upload-keystore.jks
```

### Update build.gradle.kts for signing:

```kotlin
// At the top of android {} block, before defaultConfig:
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}

android {
    // ... existing config ...

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

### Build the APK:

```powershell
# Navigate to flutter app directory
cd d:\expenseiq\expenseiq\flutter_app

# Build release APK pointing to your cloud backend
flutter build apk --release --dart-define=API_URL=https://your-backend.railway.app/api
```

The APK will be at:
```
d:\expenseiq\expenseiq\flutter_app\build\app\outputs\flutter-apk\app-release.apk
```

---

## Step 6: Data Backup Strategy

With PostgreSQL on Railway/Render, your data is automatically backed up. But for extra safety:

### Automatic Daily Backups (add to Django):

```python
# Create a management command: expenses/management/commands/backup_db.py
from django.core.management.base import BaseCommand
from django.core.management import call_command
import datetime

class Command(BaseCommand):
    help = 'Backup database to JSON fixture'

    def handle(self, *args, **options):
        filename = f'backup_{datetime.date.today().isoformat()}.json'
        with open(filename, 'w') as f:
            call_command('dumpdata', '--indent', '2', stdout=f)
        self.stdout.write(f'Backup saved to {filename}')
```

### Export from the app:
Your app already has CSV export in the Reports tab — users can use that to keep personal backups.

---

## Quick Checklist Before Release

- [ ] Backend deployed to cloud (Railway/Render)
- [ ] PostgreSQL database set up and migrated
- [ ] `DJANGO_SECRET_KEY` set to a strong random value
- [ ] `DEBUG=False` in production
- [ ] `ALLOWED_HOSTS` set to your domain
- [ ] `CORS_ALLOWED_ORIGINS` includes your app's origin
- [ ] Flutter `api_service.dart` updated with cloud URL
- [ ] App name changed from "flutter_app" to "ExpenseIQ"
- [ ] Application ID changed from "com.yourname.flutter_app"
- [ ] APK signing key created and saved
- [ ] Release APK built and tested
- [ ] Tested: register → add transaction → logout → login on another device → data visible ✅

---

## Summary of Costs

| Service | Cost | What You Get |
|---|---|---|
| Railway (backend + PostgreSQL) | Free $5/month credit | Enough for personal use |
| Render | Free tier | PostgreSQL sleeps after 90 days |
| DigitalOcean | $5/month | Full VPS, no limits |
| Play Store (optional) | $25 one-time | Distribute via Play Store |
| Direct APK sharing | **Free** | Share via WhatsApp/Drive |
