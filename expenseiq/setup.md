# 📱 ExpenseIQ — Mobile Running & Testing Guide (USB Debugging)

This guide walks you through connecting your physical Android phone via USB to run, test, and debug the **ExpenseIQ** mobile application live on your phone.

---

## 🛠️ Step 1: Enable Developer Options on Your Phone

Before connecting, your phone needs to allow development connections:
1. Open your phone's **Settings**.
2. Go to **About Phone** (or **About Device**).
3. Find **Build Number** (or **MIUI Version** for Xiaomi/POCO/Redmi) and tap it **7 times** continuously.
4. You will see a toast notification: *"You are now a developer!"*

---

## 🔌 Step 2: Enable USB Debugging Settings

Now, turn on the permissions that let your laptop install and debug apps:
1. Go back to main **Settings** -> **System** -> **Developer Options** (or **Settings** -> **Additional Settings** -> **Developer Options**).
2. Turn **ON** the main **Developer Options** switch.
3. Scroll down to the **Debugging** section and turn **ON** the following toggles:
   - ✅ **USB Debugging** (Allows basic commands and logging).
   - ✅ **Install via USB** *(CRITICAL for Xiaomi/POCO/Redmi)* — This stops the `INSTALL_FAILED_USER_RESTRICTED` error.
   - ✅ **USB Debugging (Security settings)** *(Recommended)* — Allows simulating inputs and permissions.

---

## 💻 Step 3: Connect and Verify Connection

1. Connect your phone to your laptop using a high-quality USB cable.
2. If your phone prompts with a USB mode selection, select **File Transfer** (or **MIDI**).
3. A popup will appear on your phone screen: **"Allow USB Debugging?"**
   - Check **"Always allow from this computer"** and tap **OK/Allow**.
4. To verify the connection is active, open a terminal on your laptop and run:
   ```bash
   flutter devices
   ```
   *Your phone's name (e.g., `22101316UP`) should appear in the listed devices.*

---

## 🚀 Step 4: Run the Backend & App Properly

Always run the backend first, then the frontend.

### 1️⃣ Terminal 1: Run the Django Backend
Your laptop must host the server using `0.0.0.0` so your phone can talk to it over the local network (hotspot/Wi-Fi):
```powershell
# 1. Navigate to the backend folder
cd d:\expenseiq\expenseiq\backend\expenseiq

# 2. Activate Python virtual environment
d:\expenseiq\.venv\Scripts\Activate.ps1

# 3. Start the server on all IP interfaces
python manage.py runserver 0.0.0.0:8000
```

### 2️⃣ Terminal 2: Run the Flutter App
```powershell
# 1. Navigate to the Flutter app folder
cd d:\expenseiq\expenseiq\flutter_app

# 2. Run the application on your connected phone
flutter run
```
*Note: Keep your phone unlocked. If a popup asks "Allow installation via USB?", tap **Install/Allow** immediately.*

---

## ⚡ Step 5: Interactive Terminal Commands

Once the app is running, the terminal becomes your controller. Press these keys in Terminal 2:

* **`r`** (Lowercase) ➡️ **Hot Reload**: Instantly updates the UI when you modify and save code (takes less than 1 second, maintains app state).
* **`R`** (Uppercase) ➡️ **Hot Restart**: Restarts the entire Flutter application (resets app state).
* **`q`** ➡️ **Quit**: Stops debugging and closes the app on your phone.
* **`c`** ➡️ **Clear**: Clears the console logs.

---

## 🚨 Troubleshooting

### ❌ Error: `INSTALL_FAILED_USER_RESTRICTED`
* **Cause**: Your phone blocked the laptop from pushing the app.
* **Fix**: Ensure **"Install via USB"** is turned on in your phone's Developer Options. If it fails to turn on, make sure your phone has a working SIM card inserted and you are logged into your phone brand's account (like Mi Account for Xiaomi).

### ❌ App says: `Failed to load data / Connection refused`
* **Cause**: The app's configured IP address doesn't match your laptop's current network IP address.
* **Fix**: 
  1. Open a terminal and run `ipconfig` (Windows). Find your Wi-Fi or Hotspot IPv4 address.
  2. Open `flutter_app/lib/services/api_service.dart` and update `_physicalDeviceIp` to match that IP.
  3. Save the file and press `R` to Hot Restart.
