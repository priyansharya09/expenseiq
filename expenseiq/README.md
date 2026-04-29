# ExpenseIQ — Django + Flutter Expense Manager

A full-stack personal expense & income tracking app with XLS bulk import.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend API | Django 5 + Django REST Framework |
| Auth | JWT (SimpleJWT) |
| Database | SQLite (dev) / PostgreSQL (prod) |
| Mobile App | Flutter 3.x (Dart) |
| State Management | Riverpod |
| HTTP Client | Dio |
| Charts | fl_chart |
| XLS Parsing | openpyxl, xlrd (backend) / excel (Flutter) |

---

## Prerequisites

### System Requirements

| Tool | Minimum Version | Install |
|------|----------------|---------|
| Python | 3.11+ | https://python.org |
| pip | 23+ | bundled with Python |
| Flutter SDK | 3.19+ | https://flutter.dev/docs/get-started/install |
| Dart SDK | 3.3+ | bundled with Flutter |
| Android Studio | 2023.1+ | https://developer.android.com/studio |
| Android SDK | API 21+ | via Android Studio SDK Manager |
| Java JDK | 17+ | https://adoptium.net |
| Git | any | https://git-scm.com |

### Verify your setup

```bash
python --version        # Python 3.11+
pip --version
flutter doctor          # should show all green checkmarks
dart --version
java -version           # 17+
```

---

## Project Structure

```
expenseiq/
├── backend/                    # Django Project
│   ├── expenseiq/              # Django project config
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── wsgi.py
│   ├── expenses/               # Main Django app
│   │   ├── models.py           # Transaction, Category models
│   │   ├── serializers.py      # DRF serializers
│   │   ├── views.py            # API ViewSets
│   │   ├── urls.py             # App URL routes
│   │   └── tests.py            # Unit + Integration tests
│   ├── requirements.txt
│   └── manage.py
│
└── flutter_app/                # Flutter Project
    ├── lib/
    │   ├── main.dart
    │   ├── services/
    │   │   └── api_service.dart    # Dio HTTP client + JWT
    │   ├── models/
    │   │   └── transaction.dart    # Data models
    │   ├── screens/
    │   │   ├── dashboard_screen.dart
    │   │   ├── transactions_screen.dart
    │   │   ├── add_transaction_screen.dart
    │   │   ├── bulk_upload_screen.dart
    │   │   └── auth/
    │   │       ├── login_screen.dart
    │   │       └── register_screen.dart
    │   └── widgets/
    │       ├── transaction_card.dart
    │       └── summary_card.dart
    ├── test/
    │   └── widget_test.dart        # Widget + unit tests
    └── pubspec.yaml
```

---

## Backend Setup (Django)

### Step 1 — Create virtual environment

```bash
cd expenseiq/backend
python -m venv venv

# Activate:
source venv/bin/activate        # macOS/Linux
venv\Scripts\activate           # Windows
```

### Step 2 — Install dependencies

```bash
pip install -r requirements.txt
```

### Step 3 — Initialize Django project (if starting fresh)

```bash
django-admin startproject expenseiq .
python manage.py startapp expenses
```

### Step 4 — Apply settings

Copy `settings.py` into `expenseiq/settings.py`.

Update `expenseiq/urls.py`:

```python
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', include('expenses.urls')),
]
```

### Step 5 — Run migrations

```bash
python manage.py makemigrations expenses
python manage.py migrate
```

### Step 6 — Seed categories

```bash
python manage.py shell -c "
from expenses.models import Category
cats = [
  ('x','🍔'),('transport','🚗'),('shopping','🛍'),
  ('health','💊'),('entertainment','🎬'),('salary','💰'),
  ('freelance','💼'),('utilities','💡'),('education','📚'),('other','📦')
]
for name, icon in cats:
    Category.objects.get_or_create(name=name, defaults={'icon': icon})
print('Categories seeded!')
"
```

### Step 7 — Create superuser (optional)

```bash
python manage.py createsuperuser
```

### Step 8 — Run development server

```bash
python manage.py runserver 0.0.0.0:8000
```

API is now available at: `http://localhost:8000/api/`
Admin panel: `http://localhost:8000/admin/`

---

## API Endpoints Reference

### Authentication

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register/` | Register new user |
| POST | `/api/auth/login/` | Login → returns access + refresh JWT |
| POST | `/api/auth/refresh/` | Refresh access token |
| POST | `/api/auth/logout/` | Blacklist refresh token |

### Transactions

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/transactions/` | List transactions (filterable) |
| POST | `/api/transactions/` | Create transaction |
| GET | `/api/transactions/{id}/` | Get single transaction |
| PATCH | `/api/transactions/{id}/` | Update transaction |
| DELETE | `/api/transactions/{id}/` | Delete transaction |
| GET | `/api/transactions/summary/` | Monthly income/expense summary |
| GET | `/api/transactions/monthly_trend/` | 6-month trend data |
| POST | `/api/transactions/bulk-upload/` | Upload XLS/XLSX/CSV file |

### Query Params for GET /api/transactions/

```
?month=4&year=2026         Filter by month and year
?type=income               Filter by type (income/expense)
?category=food             Filter by category name
?search=grocery            Full-text search
?page=2                    Pagination
```

### Bulk Upload XLS Format

Your XLS/XLSX file must have these column headers (flexible naming):

| Column | Required | Accepted Names |
|--------|----------|----------------|
| Date | Yes | date, transaction date |
| Name | Yes | name, description, narration |
| Amount | Yes | amount, amt, value |
| Type | Yes | type, txn_type |
| Category | No | category, cat |
| Note | No | note, notes, remarks |

Sample row: `2024-04-01 | Grocery | 3200 | expense | food | Weekly shop`

---

## Flutter App Setup

### Step 1 — Create Flutter project

```bash
flutter create expenseiq --org com.yourname
cd expenseiq
```

### Step 2 — Replace pubspec.yaml

Copy the provided `pubspec.yaml` and run:

```bash
flutter pub get
```

### Step 3 — Configure API base URL

In `lib/services/api_service.dart`, set:

```dart
// Android emulator → Django on same machine
static const String baseUrl = 'http://10.0.2.2:8000/api';

// iOS simulator → Django on same machine
static const String baseUrl = 'http://localhost:8000/api';

// Physical device → use your machine's LAN IP
static const String baseUrl = 'http://192.168.1.x:8000/api';
```

### Step 4 — Android permissions

Add to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

For Android 9+, also add inside `<application>`:

```xml
android:usesCleartextTraffic="true"
```

### Step 5 — Run the app

```bash
# List available devices
flutter devices

# Run on Android emulator
flutter run

# Run on specific device
flutter run -d emulator-5554

# Build release APK
flutter build apk --release

# APK is at: build/app/outputs/flutter-apk/app-release.apk
```

---

## Running Tests

### Django Backend Tests

```bash
cd backend
source venv/bin/activate

# Run all tests
python manage.py test expenses

# Run specific test class
python manage.py test expenses.tests.TransactionAPITest

# Run with verbose output
python manage.py test expenses -v 2

# Run with coverage
pip install coverage
coverage run manage.py test expenses
coverage report
coverage html  # open htmlcov/index.html
```

Expected output:
```
Found 20 tests...
....................
----------------------------------------------------------------------
Ran 20 tests in 3.241s
OK
```

### Flutter Tests

```bash
cd flutter_app

# Run all tests
flutter test

# Run with coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html

# Run specific test file
flutter test test/widget_test.dart

# Run with verbose output
flutter test -v
```

### Integration Tests (End-to-End)

```bash
# Make sure backend is running first
python manage.py runserver

# In flutter_app directory
flutter test integration_test/app_test.dart
```

---

## Environment Variables (Backend)

Create a `.env` file in the `backend/` directory:

```env
DJANGO_SECRET_KEY=your-super-secret-key-here
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1,10.0.2.2
DB_ENGINE=django.db.backends.sqlite3
```

For production, use PostgreSQL and set:

```env
DEBUG=False
DB_ENGINE=django.db.backends.postgresql
DB_NAME=expenseiq
DB_USER=postgres
DB_PASSWORD=yourpassword
DB_HOST=localhost
DB_PORT=5432
```

---

## Building Release APK

```bash
cd flutter_app

# Generate keystore (one-time setup)
keytool -genkey -v -keystore ~/expenseiq.keystore \
  -alias expenseiq -keyalg RSA -keysize 2048 -validity 10000

# Build release APK
flutter build apk --release

# APK location
build/app/outputs/flutter-apk/app-release.apk

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

---

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| `Connection refused` on Android emulator | Use `10.0.2.2` instead of `localhost` |
| CORS errors | Ensure `django-cors-headers` installed and `CORS_ALLOW_ALL_ORIGINS=True` in DEBUG |
| `cleartext HTTP` error on Android | Add `android:usesCleartextTraffic="true"` in AndroidManifest |
| JWT token expired | App auto-refreshes via Dio interceptor |
| XLS upload fails | Ensure column headers match the required names (case-insensitive) |
| `flutter doctor` issues | Run `flutter doctor --android-licenses` to accept SDK licenses |
