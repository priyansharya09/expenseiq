# 📶 ExpenseIQ — Wireless Debugging Setup Guide (Wi-Fi)

This guide walks you through connecting your Android phone to your laptop wirelessly. This allows you to run, test, and debug the **ExpenseIQ** mobile app without using a USB cable!

> **Prerequisite:** Both your laptop and your phone **must be connected to the same Wi-Fi network** (or your laptop must be connected to your phone's hotspot).

---

## Method 1: Android 11 and above (No USB cable needed at all)

Android 11+ supports native Wireless Debugging without needing a cable to set it up initially.

### Step 1: Enable Wireless Debugging on Phone
1. Go to **Settings** -> **Developer Options**.
2. Scroll down to the **Debugging** section.
3. Turn **ON** the **Wireless debugging** toggle.
4. Tap **Allow** on the prompt that asks "Allow wireless debugging on this network?".
5. **Tap on the words "Wireless debugging"** to open its specific settings page.

### Step 2: Pair the Device
1. On the Wireless Debugging screen, tap **Pair device with pairing code**.
2. A popup will appear showing a **Wi-Fi pairing code**, an **IP address**, and a **Port** (e.g., `192.168.1.5:43210`).
3. Open a terminal on your laptop and run:
   ```bash
   adb pair <IP_ADDRESS>:<PORT>
   # Example: adb pair 192.168.1.5:43210
   ```
4. When prompted in the terminal, enter the **Wi-Fi pairing code** shown on your phone.

### Step 3: Connect the Device
1. Look back at the main **Wireless debugging** screen on your phone (under "IP address & Port"). It will show a different connection port (e.g., `192.168.1.5:38987`).
2. In your laptop terminal, run:
   ```bash
   adb connect <IP_ADDRESS>:<PORT>
   # Example: adb connect 192.168.1.5:38987
   ```
3. Run `flutter devices` or `adb devices` in the terminal to verify your phone is connected wirelessly!

---

## Method 2: Android 10 and below (Requires USB cable for initial setup)

If your phone is on Android 10 or older, you need a USB cable just to start the wireless connection.

### Step 1: Initialize TCP/IP connection
1. Connect your phone to your laptop using a USB cable.
2. Ensure regular **USB Debugging** is turned ON in Developer Options.
3. Open a terminal on your laptop and run:
   ```bash
   adb tcpip 5555
   ```
4. Unplug the USB cable from your phone.

### Step 2: Find Phone's IP Address
1. Go to your phone's **Settings** -> **Wi-Fi** (or **Network & Internet**).
2. Tap on your connected Wi-Fi network to view its details.
3. Note down the **IP address** (e.g., `192.168.1.15`).

### Step 3: Connect Wirelessly
1. In your laptop terminal, run:
   ```bash
   adb connect <YOUR_PHONE_IP_ADDRESS>:5555
   # Example: adb connect 192.168.1.15:5555
   ```
2. Run `flutter devices` or `adb devices` to verify it's connected.
*(Note: You will have to repeat these steps every time you restart your phone).*

---

## 🚀 Running the App Wirelessly

Once your device is connected via Wi-Fi, you run the app exactly the same way as you do with a USB cable!

### Terminal 1: Django Backend
Make sure your Django server is running on `0.0.0.0` so the phone can access it over Wi-Fi.
```powershell
cd d:\expenseiq\expenseiq\backend\expenseiq
d:\expenseiq\.venv\Scripts\Activate.ps1
python manage.py runserver 0.0.0.0:8000
```

### Terminal 2: Flutter App
```powershell
cd d:\expenseiq\expenseiq\flutter_app
flutter run
```

---

## 🚨 Troubleshooting

### ❌ `adb: command not found` or `adb is not recognized`
* **Cause**: Your computer doesn't know where the Android Debug Bridge (ADB) tool is located.
* **Fix**: You need to run ADB from the platform-tools folder or add it to your system PATH.
  * Usually located at: `C:\Users\<YourUsername>\AppData\Local\Android\Sdk\platform-tools\`
  * You can navigate there in your terminal: `cd $env:LOCALAPPDATA\Android\Sdk\platform-tools` and run `./adb connect ...`

### ❌ Flutter App says: `Connection refused`
* **Fix**: Ensure `_physicalDeviceIp` in `flutter_app/lib/services/api_service.dart` is set to your **laptop's** Wi-Fi IP address (found by running `ipconfig` on your laptop).

### ❌ Disconnections / Lag
* **Fix**: Wireless debugging requires a stable Wi-Fi network. If it keeps disconnecting, use a Mobile Hotspot from your laptop to your phone for a direct connection, or switch back to USB debugging.
