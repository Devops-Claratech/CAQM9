# Claratech AQM9 Air Quality Monitor
 
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform](https://img.shields.io/badge/Platform-ESP32-green.svg)](https://www.espressif.com/)
[![Firmware](https://img.shields.io/badge/Firmware-TASMOTA-orange.svg)](https://tasmota.github.io/)
 
A comprehensive air quality monitor that tracks CO2, particulate matter, VOCs, NOx, temperature, humidity, and atmospheric pressure. Built on ESP32 hardware with TASMOTA firmware, featuring an OLED display, RGB LED indicators, and audible pollution alerts.
 
**Product Website**: <https://caqm.io>
 
[![Claratech AQM9 Air Quality Monitor](https://github.com/Devops-Claratech/CAQM9/raw/main/Docs/Claratech-AQM9.png)](/Devops-Claratech/CAQM9/blob/main/Docs/Claratech-AQM9.png)
 
## Features
 
* Real-time monitoring of multiple air quality parameters
* Visual LED indicators with color-coded pollution levels
* OLED display with multiple viewing modes
* Audible alerts for high pollution events
* WiFi connectivity with web interface
* Automatic temperature compensation
* CO2 sensor calibration support
* Configurable auto-restart for long-term stability
## Development
 
This project uses [Berry](https://berry.readthedocs.io/) scripting language on the TASMOTA firmware platform.
 
### Key References
 
* [Berry Language Reference](https://berry.readthedocs.io/en/latest/source/en/Reference.html)
* [Berry Builtin Modules](https://berry.readthedocs.io/en/latest/source/en/Chapter-7.html)
* [Tasmota Berry Cookbook](https://tasmota.github.io/docs/Berry-Cookbook/)
* [Tasmota Documentation](https://tasmota.github.io/docs/)
### Code Structure
 
The driver consists of two main classes:
 
* **DisplaySensorDriver** - Core sensor reading, display output, LED control, and alert management
* **MenuManager** - User interface and settings navigation
## Sensors
 
| Sensor | Measurements |
| --- | --- |
| MHZ19B | CO2 (ppm) |
| PMS5003 | PM1, PM2.5, PM10 (µg/m³) |
| SGP41 | VOC Index, NOx Index |
| BME280 | Temperature, Humidity, Atmospheric Pressure |
 
## LED Indicators
 
Three RGB LEDs provide at-a-glance air quality status:
 
| LED | Sensor |
| --- | --- |
| LED 1 | CO2 |
| LED 2 | PM2.5 |
| LED 3 | VOC/NOx (shows worst of the two) |
 
**LED Colors:**
 
* **Green** - Good air quality
* **Orange** - Moderate levels
* **Red** - High pollution
* **Violet** - Very high pollution
### Pollution Thresholds
 
| Pollutant | Normal | Moderate | High |
| --- | --- | --- | --- |
| CO2 (ppm) | ≤800 | ≤1200 | ≤2000 |
| PM2.5 (µg/m³) | ≤5 | ≤20 | ≤50 |
| VOC Index | ≤100 | ≤200 | ≤350 |
| NOx Index | ≤1 | ≤20 | ≤200 |
 
## Display Modes
 
The OLED display supports three viewing modes:
 
1. **All in One** - Shows all sensor readings simultaneously
2. **Auto Scroll** - Cycles through each sensor value one at a time
3. **PM2.5 Only** - Displays only PM2.5 readings
## Button Controls
 
### Button 1 (Options)
 
Quick actions when not in menu:
 
* **Single press** - Toggle display on/off
* **Double press** - Toggle LEDs on/off
* **Triple press** - Show WiFi IP address
* **Quad press** - Toggle buzzer on/off
* **Hold** - Toggle WiFi on/off
### Button 2 (Menu)
 
* **Press** - Enter menu / Navigate down
* **Hold** - Exit menu
### In Menu Mode
 
* **Button 1** - Navigate up / Confirm selection
* **Button 2** - Navigate down / Confirm selection
## Menu System
 
```
Main Menu
├── 1. General
│   ├── 1. LED/Buzzer
│   │   ├── LED Brightness (100%, 50%, 30%)
│   │   └── Buzzer ON/OFF
│   ├── 2. Display Mode
│   │   ├── All in one
│   │   ├── Auto Scroll
│   │   └── PM2.5 Only
│   ├── 3. Temp Scale (Celsius/Fahrenheit)
│   └── 4. WiFi
│       ├── WiFi Info
│       ├── WiFi On/Off
│       └── Reset WiFi
├── 2. Sensor
│   ├── 1. CO2 Calibration
│   └── 2. PMS Poll Time (1min, 5min, Continuous)
└── 3. About
```
 
## Custom Commands
 
Access these commands via the TASMOTA console or web interface:
 
### `caqm`
 
Returns current sensor data in JSON format:
 
```
{"AirQuality":1,"CarbonDioxide":450,"PM1":2,"PM2.5":5,"PM10":8,"TVOC":85,"NO2":1}
```
 
The `AirQuality` value (1-4) represents overall air quality based on the worst reading.
 
### `autotemp [0|1]`
 
Enable or disable automatic temperature offset compensation.
 
```
autotemp 0    # Disable auto temperature offset
autotemp 1    # Enable auto temperature offset
autotemp      # Show current setting
```
 
The device automatically adjusts temperature readings to compensate for internal heat during operation.
 
### `autorestart [0-23]`
 
Set an automatic restart interval in hours for long-term stability.
 
```
autorestart 0     # Disable auto restart
autorestart 12    # Restart every 12 hours
autorestart       # Show current setting
```
 
## CO2 Calibration
 
To calibrate the CO2 sensor:
 
1. Place the device outside in fresh air for at least 10 minutes
2. Navigate to **Menu > Sensor > CO2 Calibration**
3. Confirm calibration
This sets the current reading as the 400ppm baseline.
 
## WiFi Setup
 
On first boot or after WiFi reset:
 
1. The device creates an access point named `tasmota-XXXXXX-XXXX`
2. Connect to this network
3. Navigate to `192.168.4.1` in your browser
4. Enter your WiFi credentials
## Technical Specifications
 
| Specification | Value |
| --- | --- |
| Platform | ESP32 |
| Firmware | TASMOTA |
| Driver Language | Berry |
| LED Type | WS2812 RGB |
| LED GPIO | 18 |
| Display | OLED |
 
## Memory Allocation
 
The driver uses TASMOTA memory variables for persistent storage:
 
| Memory | Purpose |
| --- | --- |
| Mem9 | Last uptime for auto temperature offset |
| Mem10 | Last time check for auto temperature offset |
| Mem11 | Auto-restart interval (hours) |
| Mem12 | Temperature offset enabled (0/1) |
| Mem13 | Telegram poll time |
| Mem14 | LED brightness (10-100) |
| Mem15 | Display mode (0=all, 1=scroll, 2=PM only) |
| Mem16 | Buzzer on/off |
 
## Installation
 
There are two paths to get a working AQM9, depending on whether you're using a Claratech-assembled device or building one yourself.
 
### Path A: Pre-flashed device (most users)
 
If you bought your AQM9 from Claratech, it ships pre-flashed and ready to use. To update the Berry driver to the latest version:
 
1. Download the latest `AQM_Driver.be` and `autoexec.be` from this repository
2. Upload both files to the device filesystem via the Tasmota web UI (**Consoles → Manage File system**)
3. Restart the device
The `autoexec.be` file automatically loads the driver on boot.
 
### Path B: Build from source (DIY)
 
If you assembled your own AQM9 from the [open hardware files](https://oshwlab.com/claratech/claratech-aqm9-mainboard) — or you want to compile the firmware yourself for full transparency — you'll need to build a custom Tasmota binary first. The stock Tasmota firmware doesn't include everything the AQM9 needs, so a build prep step is required.
 
1. **Prepare the Tasmota source** using the build prep tool: **[CAQM9_Tasmota_Code_Prep](https://github.com/Devops-Claratech/CAQM9_Tasmota_Code_Prep)**. This repo contains a Python script and the `user_config_override.h` needed to patch the Tasmota source tree (relocates I2C libraries for ESP32, enables the buzzer, expands humidity offset range, etc.).
2. **Compile the firmware** with PlatformIO using your preferred ESP32 environment.
3. **Flash the compiled binary** to your ESP32 (see the *Firmware Recovery* section below for example `esptool` commands).
4. **Upload the Berry driver**: copy `AQM_Driver.be` and `autoexec.be` from this repository to the device filesystem.
5. **Restart the device.**
## Firmware Recovery
 
> ⚠️ **Do not use Tasmota's built-in OTA upgrade on the AQM9.**
>
> Stock Tasmota releases don't include the sensor libraries the AQM9 needs (SGP41, buzzer support, and an expanded humidity offset range). Upgrading via the Tasmota web UI **will** leave the device in a broken state where the OLED, LEDs, and sensor readings stop working, even though the device still appears online. If we publish a new firmware version, it will go up in the Google Drive folder below and be announced — flash it over USB using the instructions in this section.
 
If a Tasmota OTA upgrade has already broken your device, or you need to restore your AQM9 to its original shipping state, the factory firmware is available here:
 
**[CAQM9 Firmware Binaries (Google Drive)](https://drive.google.com/drive/folders/17RJQBsM249BZxEqUaX-_uqHvYXwHp_WY?usp=sharing)**
 
The folder contains:
 
* `CAQM9-Tasmota-15.3.0-Driver-1.92-WiFi-OFF.bin` — the exact firmware the AQM9 ships with (Tasmota 15.3.0 + Driver v1.92, WiFi disabled by default)
* `Readme.txt` — step-by-step `esptool` flashing instructions for macOS, Windows, and Linux
Quick flash command (replace `<PORT>` with your serial port):
 
```
esptool --port <PORT> --baud 460800 \
        --before default-reset --after hard-reset \
        write-flash --flash-mode dio --flash-freq 80m --flash-size 4MB \
        0 CAQM9-Tasmota-15.3.0-Driver-1.92-WiFi-OFF.bin
```
 
After flashing, WiFi is off by default. Enable it via **Button 1 (hold)** or **Menu → General → WiFi → WiFi On/Off**.
 
## License
 
This software is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0).
 
Copyright (C) 2026, Claratech Innovations Pvt. Ltd.
 
## Contact
 
* **Website**: <https://caqm.io>
* **Email**: [team@claratech.cx](mailto:team@claratech.cx)
 
