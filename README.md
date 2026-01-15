# Claratech AQM9 Air Quality Monitor

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform](https://img.shields.io/badge/Platform-ESP32-green.svg)](https://www.espressif.com/)
[![Firmware](https://img.shields.io/badge/Firmware-TASMOTA-orange.svg)](https://tasmota.github.io/)

A comprehensive air quality monitor that tracks CO2, particulate matter, VOCs, NOx, temperature, humidity, and atmospheric pressure. Built on ESP32 hardware with TASMOTA firmware, featuring an OLED display, RGB LED indicators, and audible pollution alerts.

**Product Website**: [https://caqm.io](https://caqm.io)

## Features

- Real-time monitoring of multiple air quality parameters
- Visual LED indicators with color-coded pollution levels
- OLED display with multiple viewing modes
- Audible alerts for high pollution events
- WiFi connectivity with web interface
- Automatic temperature compensation
- CO2 sensor calibration support
- Configurable auto-restart for long-term stability

## Development

This project uses [Berry](https://berry.readthedocs.io/) scripting language on the TASMOTA firmware platform.

### Key References

- [Berry Language Reference](https://berry.readthedocs.io/en/latest/source/en/Reference.html)
- [Berry Builtin Modules](https://berry.readthedocs.io/en/latest/source/en/Chapter-7.html)
- [Tasmota Berry Cookbook](https://tasmota.github.io/docs/Berry-Cookbook/)
- [Tasmota Documentation](https://tasmota.github.io/docs/)

### Code Structure

The driver consists of two main classes:

- **DisplaySensorDriver** - Core sensor reading, display output, LED control, and alert management
- **MenuManager** - User interface and settings navigation

## Sensors

| Sensor | Measurements |
|--------|--------------|
| MHZ19B | CO2 (ppm) |
| PMS5003 | PM1, PM2.5, PM10 (µg/m³) |
| SGP41 | VOC Index, NOx Index |
| BME280 | Temperature, Humidity, Atmospheric Pressure |

## LED Indicators

Three RGB LEDs provide at-a-glance air quality status:

| LED | Sensor |
|-----|--------|
| LED 1 | CO2 |
| LED 2 | PM2.5 |
| LED 3 | VOC/NOx (shows worst of the two) |

**LED Colors:**
- **Green** - Good air quality
- **Orange** - Moderate levels
- **Red** - High pollution
- **Violet** - Very high pollution

### Pollution Thresholds

| Pollutant | Normal | Moderate | High |
|-----------|--------|----------|------|
| CO2 (ppm) | ≤800 | ≤1200 | ≤2000 |
| PM2.5 (µg/m³) | ≤5 | ≤20 | ≤50 |
| VOC Index | ≤100 | ≤200 | ≤350 |
| NOx Index | ≤1 | ≤20 | ≤200 |

## Installation

1. Flash TASMOTA firmware to your ESP32 device
2. Copy both `AQM_Driver.be` and `autoexec.be` to the device filesystem
3. Restart the device

The `autoexec.be` file automatically loads the driver on boot.

## Display Modes

The OLED display supports three viewing modes:

1. **All in One** - Shows all sensor readings simultaneously
2. **Auto Scroll** - Cycles through each sensor value one at a time
3. **PM2.5 Only** - Displays only PM2.5 readings

## Button Controls

### Button 1 (Options)

Quick actions when not in menu:
- **Single press** - Toggle display on/off
- **Double press** - Toggle LEDs on/off
- **Triple press** - Show WiFi IP address
- **Quad press** - Toggle buzzer on/off
- **Hold** - Toggle WiFi on/off

### Button 2 (Menu)

- **Press** - Enter menu / Navigate down
- **Hold** - Exit menu

### In Menu Mode

- **Button 1** - Navigate up / Confirm selection
- **Button 2** - Navigate down / Confirm selection

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

```json
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
|---------------|-------|
| Platform | ESP32 |
| Firmware | TASMOTA |
| Driver Language | Berry |
| LED Type | WS2812 RGB |
| LED GPIO | 18 |
| Display | OLED |

## Memory Allocation

The driver uses TASMOTA memory variables for persistent storage:

| Memory | Purpose |
|--------|---------|
| Mem9 | Last uptime for auto temperature offset |
| Mem10 | Last time check for auto temperature offset |
| Mem11 | Auto-restart interval (hours) |
| Mem12 | Temperature offset enabled (0/1) |
| Mem13 | Telegram poll time |
| Mem14 | LED brightness (10-100) |
| Mem15 | Display mode (0=all, 1=scroll, 2=PM only) |
| Mem16 | Buzzer on/off |

## License

This software is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0).

Copyright (C) 2026, Claratech Innovations Pvt. Ltd.

## Contact

- **Website**: [https://caqm.io](https://caqm.io)
- **Email**: info@claratech.cx
