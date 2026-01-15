#-
    Claratech AQM9 Driver 
    Copyright (C) 2026, Claratech Innovations Pvt. Ltd.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>. 
    
    info@claratech.cx
-#



import json
import string



class DisplaySensorDriver
    # Tasmota Memory Allocation for Sensor Configuration
    # Mem9: Last uptime for auto temperature offset
    # Mem10: Last time check for auto temperature offset
    # Mem11: Auto-restart setting
    # Mem12: Temperature offset setting
    # Mem13: Telegram poll time
    # Mem14: LED brightness
    # Mem15: Display mode
    # Mem16: Buzzer on/off

    # Firmware and hardware details
    static var Product_version = "1.91"
    static var Product_model = "AQM9"
    static var Manufacturer = "CLARATECH"

    # Startup flags
    var onceonstartup1
    var onceonstartup2
    
    # System tick counter
    var tick

    # Sensor type identifiers
    static var SENSOR_CO2 = 1
    static var SENSOR_PMS = 2
    static var SENSOR_VOC = 3
    static var SENSOR_NOX = 4

    # Consolidated sensor configuration and state
    var sensors
    var sensor_types

    # Sensor readings
    var co2_value
    var pm25_value
    var pm10_value
    var pm1_value
    var voc_raw_value
    var voc_index_value    
    var nox_raw_value
    var nox_index_value
    var aht_temp
    var aht_hum
    var aht_hpa

    # LED and buzzer state
    var led1 # CO2
    var led2 # PM
    var led3 # VOC
    var buzzer_active

    # Display and LED settings
    var display_mode
    var display_mode_previous
    var sensor_led_brightness
    var sensor_led_brightness_default
    
    # Temperature and time settings
    var esp_temp
    var tempoffset
    var temp_scale_st
    var cold_start
    var time_to_cold_start

    # Display layout
    var liney
    
    # Tasmota system variable mappings
    static var displaysensorinfo = 16 # Var16: Toggles sensor info on display
    static var sensor_led_on = 15     # Var15: Toggles sensor LEDs
    static var startup_complete = 14  # Var14: Flag for startup completion

    # Index for scrolling sensor values
    var show_sensor_indx

    # Counter limit for level changes to prevent rapid alerts
    var level_change_count_limit

    # Overall air quality indicator
    var air_quality
    
    # Auto-restart settings
    var autorestart_hrs
    var current_uptime_hrs

    # Post-warning screen clear flag
    var clear_screen_after_warning
    
    # Returns the unique device ID based on the hardware MAC address.
    def get_device_id() 
        var networkinfo = tasmota.cmd("status 5")["StatusNET"]
        var mac = networkinfo["Mac"]
        var devid = mac
        devid = string.tr(devid, ":", "")
        return devid
    end

    # Reads a value from a specified Tasmota memory slot.
    static def get_sys_mem(num)
        var zero = -1
        try
            var val = tasmota.cmd("Mem" + str(num))
            val = val["Mem" + str(num)]
            return val
        except 'key_error'
            print("Key error reading Mem variable")
            return zero    
        end
    end

    # Reads a value from a Tasmota memory slot and converts it to a number.
    static def get_sys_mem_as_number(num)
        return number(DisplaySensorDriver.get_sys_mem(num))
    end

    # Writes a value to a specified Tasmota memory slot.
    static def set_sys_mem_num(num, val)
        tasmota.cmd("Mem" + str(num) + " " + str(val))
    end

    # Updates the buzzer, display mode, and LED brightness settings from memory.
    def update_buzzer_and_display_mode_state()
        var mem
        mem = self.get_sys_mem_as_number(16)
        if mem >= 0
            if mem == 0
                self.buzzer_active = false
            else 
                self.buzzer_active = true
            end
        end

        mem = self.get_sys_mem_as_number(15)
        if mem >= 0
            self.display_mode = mem
        end

        mem = self.get_sys_mem_as_number(14)
        if mem >= 10 && mem <= 100
            self.sensor_led_brightness = mem
        else 
            self.sensor_led_brightness = self.sensor_led_brightness_default
            self.set_sys_mem_num(14, self.sensor_led_brightness)
        end
    end

    # Calculates and returns the device uptime in hours.
    def get_uptime_hrs()
        return (((tasmota.millis() / 1000) / 60) / 60) 
    end

    # Calculates the time in minutes since the last reboot.
    static def get_reboot_after_mins()
        var last_timecheck = number(DisplaySensorDriver.get_sys_mem_as_number(10))
        var utc = number(tasmota.rtc()['utc'])
        var uptime_mins  = 0
        var reboot_after_mins = ((utc - last_timecheck)) / 60
        print("in reboot_after_mins " + str(reboot_after_mins))
        return reboot_after_mins
    end

    # Sets the temperature scale (Celsius or Fahrenheit) based on Tasmota settings.
    def set_temp_scale()
        var val = tasmota.cmd("SetOption8")
        if string.find(str(val), "ON") >= 0
            self.temp_scale_st = "F"
        else
            self.temp_scale_st = "C"
        end
    end

    # Reads a value from a specified Tasmota system variable.
    static def get_sys_var(num)
        var val = tasmota.cmd("Var" + str(num))
        return val["Var" + str(num)]
    end

    # Reads a Tasmota system variable and returns it as a boolean.
    static def get_sys_var_bool(num)
        var val = tasmota.cmd("Var" + str(num))
        val = val["Var" + str(num)]
        if val == "1"
            return true
        else 
            return false
        end
    end

    # Writes a boolean value to a specified Tasmota system variable.
    static def set_sys_var_bool(num, val)
        if val == true
            tasmota.cmd("Var" + str(num) + " 1")
        else 
            tasmota.cmd("Var" + str(num) + " 0")
        end
    end

    # Turns off all sensor LEDs.
    def leds_off()
        self.led1.set_pixel_color(0, 0x000000)
        self.led1.show()
        self.led2.set_pixel_color(1, 0x000000)
        self.led2.show()
        self.led3.set_pixel_color(2, 0x000000)
        self.led3.show()
    end

    def _init_settings_and_flags()
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, false)
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.sensor_led_on, true)
        self.sensor_led_brightness_default = 50
        self.sensor_led_brightness = self.sensor_led_brightness_default
        self.display_mode = 0
        self.display_mode_previous = 0
        self.update_buzzer_and_display_mode_state()
        self.display_mode_previous = self.display_mode
        self.onceonstartup1 = false
        self.onceonstartup2 = false
        self.cold_start = true
        self.time_to_cold_start = 8
        self.set_temp_scale()
    end

    def _init_leds()
        self.led1 = Leds(3, 18, Leds.WS2812_GRB)
        self.led2 = self.led1
        self.led3 = self.led1
        if !DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.startup_complete)
            self.leds_off()
        end
    end

    def _init_sensor_thresholds()
        # List of sensor types for iteration (Berry maps don't have reliable keys())
        self.sensor_types = [DisplaySensorDriver.SENSOR_CO2, DisplaySensorDriver.SENSOR_PMS,
                             DisplaySensorDriver.SENSOR_VOC, DisplaySensorDriver.SENSOR_NOX]

        # Consolidated sensor configuration: thresholds, state, and alert settings
        self.sensors = {
            1: {  # CO2
                'normal': 800, 'moderate': 1200, 'high': 2000,
                'led_color': 0, 'last_level': 0, 'change_count': 0,
                'alert_pct': 105
            },
            2: {  # PMS (PM2.5)
                'normal': 5, 'moderate': 20, 'high': 50,
                'led_color': 0, 'last_level': 0, 'change_count': 0,
                'alert_pct': 120
            },
            3: {  # VOC
                'normal': 100, 'moderate': 200, 'high': 350,
                'led_color': 0, 'last_level': 0, 'change_count': 0,
                'alert_pct': 105
            },
            4: {  # NOx
                'normal': 1, 'moderate': 20, 'high': 200,
                'led_color': 0, 'last_level': 0, 'change_count': 0,
                'alert_pct': 105
            }
        }
    end

    def _init_variables()
        self.liney = [0, 14, 28, 42, 54]
        self.tick = 0
        self.co2_value = -1
        self.pm10_value = 0
        self.pm1_value = 0
        self.pm25_value = -1
        self.voc_raw_value = nil
        self.voc_index_value = -1
        self.nox_raw_value = nil
        self.nox_index_value = -1
        self.aht_temp = nil
        self.aht_hum = nil
        self.aht_hpa = nil
        self.show_sensor_indx = 0
        self.buzzer_active = true
        self.level_change_count_limit = 60
        self.esp_temp = 0
        self.tempoffset = 0
        self.air_quality = 0
        self.autorestart_hrs = DisplaySensorDriver.get_sys_mem_as_number(11)
        self.current_uptime_hrs = 0
        self.clear_screen_after_warning = false
    end

    # Returns the current value for a given sensor type
    def get_sensor_value(sensor_type)
        if sensor_type == DisplaySensorDriver.SENSOR_CO2
            return self.co2_value
        elif sensor_type == DisplaySensorDriver.SENSOR_PMS
            return self.pm25_value
        elif sensor_type == DisplaySensorDriver.SENSOR_VOC
            return self.voc_index_value
        elif sensor_type == DisplaySensorDriver.SENSOR_NOX
            return self.nox_index_value
        end
        return -1
    end

    # Returns the pollution level (1-4) based on value and thresholds
    def get_pollution_level(value, normal, moderate, high)
        if value <= normal
            return 1
        elif value <= moderate
            return 2
        elif value <= high
            return 3
        end
        return 4
    end

    # Initializes the driver, setting up default values and configurations.
    def init()
        self._init_settings_and_flags()
        self._init_leds()
        self._init_sensor_thresholds()
        self._init_variables()
        self.load_sensor_values()
    end


    # Sets the color of a specific LED based on the given color code.
    def setledstate(lednum, color)
        var colormap = {
            1: 0x00FF00, # Green
            2: 0xFF9900, # Orange
            3: 0xFF0000, # Red
            4: 0x8F00FF  # Violet
        }
        var colr = colormap[color]
        var led = self.led1
        
        var bri = self.sensor_led_brightness
        if !DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.sensor_led_on)
            bri = 0
        end
        
        led.set_pixel_color((lednum - 1), colr, bri)
        led.show()
    end

    # Determines if sensor values are significantly above set limits to trigger a beep.
    # This prevents alerts from rapid fluctuations around a threshold.
    def is_level_well_above_setlimits(sensor_type)
        var cfg = self.sensors.find(sensor_type)
        if cfg == nil
            return false
        end

        var value = self.get_sensor_value(sensor_type)
        var pct = cfg['alert_pct']

        var newnormal = (cfg['normal'] * pct) / 100
        var newmedium = (cfg['moderate'] * pct) / 100
        var newhigh = (cfg['high'] * pct) / 100

        if value >= newnormal || value >= newmedium || value >= newhigh
            if cfg['change_count'] >= self.level_change_count_limit
                return true
            end
        end
        return false
    end

    # Activates the buzzer for a specified number of beeps.
    def buzzer(beeps)
        if self.buzzer_active 
            for i: 0..beeps - 1
                tasmota.cmd("buzzer " + str(beeps) + ",2,2")
            end
        end
    end

    def _get_sensor_value(sensors, key1, key2, default_value)
        try
            return sensors[key1][key2]
        except 'key_error'
            print("Key error reading " + key1 + " " + key2)
            return default_value
        end
    end

    # Reads the latest sensor values from the Tasmota device.
    def load_sensor_values()
        var sensors = tasmota.cmd("status 10")["StatusSNS"]
        
        self.co2_value = self._get_sensor_value(sensors, 'MHZ19B', 'CarbonDioxide', -1)
        
        self.pm1_value = self._get_sensor_value(sensors, 'PMS5003', 'PM1', -1)
        self.pm25_value = self._get_sensor_value(sensors, 'PMS5003', 'PM2.5', -1)
        self.pm10_value = self._get_sensor_value(sensors, 'PMS5003', 'PM10', -1)

        self.voc_raw_value = self._get_sensor_value(sensors, 'SGP41', 'VOC_Raw', nil)
        self.voc_index_value = self._get_sensor_value(sensors, 'SGP41', 'TVOC', 0)
        self.nox_raw_value = self._get_sensor_value(sensors, 'SGP41', 'NOX_Raw', nil)
        self.nox_index_value = self._get_sensor_value(sensors, 'SGP41', 'NOx', 0)
        
        if self.voc_index_value == nil
            self.voc_index_value = 0
        end
        if self.nox_index_value == nil
            self.nox_index_value = 0
        end

        self.aht_hpa = self._get_sensor_value(sensors, 'BME280', 'Pressure', nil)
        self.aht_temp = self._get_sensor_value(sensors, 'BME280', 'Temperature', nil)
        self.aht_hum = self._get_sensor_value(sensors, 'BME280', 'Humidity', nil)

        #- self.esp_temp = self._get_sensor_value(sensors, 'ESP32', 'Temperature', self.aht_temp) -#
    end

    def _get_uptime_for_offset()
        var last_uptime = DisplaySensorDriver.get_sys_mem_as_number(9)
        var uptime_mins = (tasmota.millis() / 1000) / 60

        if !self.cold_start
            if last_uptime >= 91
                uptime_mins = 91
            else
                uptime_mins = last_uptime + 1
            end
        end
        
        if uptime_mins > 90
            uptime_mins = 91
        end
        
        return uptime_mins
    end

    def _calculate_temp_offset(uptime_mins)
        var new_offset = 0
        var offset_map = [
            [5, -0.5], [8, -1.25], [12, -2], [18, -3], [30, -3.5],
            [60, -4], [90, -4.5], [91, -5]
        ]

        for i: 0..size(offset_map)-1
            var entry = offset_map[i]
            if uptime_mins <= entry[0]
                new_offset = entry[1]
                return new_offset
            end
        end
        
        return -5 # Default to max offset if not found in map
    end

    def _apply_offsets(temp_offset, uptime_mins)
        var new_hum_offset = ((temp_offset * -1) * 4) 
        var tempscaleF = tasmota.cmd("so8")['SetOption8']
        
        var final_temp_offset = temp_offset
        if tempscaleF == 'ON'
            final_temp_offset = temp_offset * 2
        end

        if final_temp_offset != self.tempoffset
            tasmota.cmd("tempoffset " + str(final_temp_offset))
            tasmota.cmd("humoffset " + str(new_hum_offset))
            self.tempoffset = final_temp_offset
        end

        DisplaySensorDriver.set_sys_mem_num(9, uptime_mins)
        DisplaySensorDriver.set_sys_mem_num(10, tasmota.rtc()["utc"])
    end

    # Adjusts the temperature and humidity offsets based on device uptime to compensate for internal heat.
    def set_tempoffset()
        var toffset_status = self.get_sys_mem_as_number(12)
        
        if toffset_status <= 0
            log("Auto temp-offet is disabled")
            return
        end

        var uptime_mins = self._get_uptime_for_offset()
        var new_temp_offset = self._calculate_temp_offset(uptime_mins)
        self._apply_offsets(new_temp_offset, uptime_mins)
    end
  
    # Updates all sensor LED colors based on current readings
    def update_led_colors()
        for sensor_type: self.sensor_types
            var cfg = self.sensors.find(sensor_type)
            if cfg != nil
                var value = self.get_sensor_value(sensor_type)
                cfg['led_color'] = self.get_pollution_level(value, cfg['normal'], cfg['moderate'], cfg['high'])
            end
        end
    end

    # Returns LED color for a sensor type from the config
    def get_led_color(sensor_type)
        var cfg = self.sensors.find(sensor_type)
        if cfg != nil
            return cfg['led_color']
        end
        return 0
    end

    # Updates all LEDs based on the latest sensor readings.
    def shineleds()
        self.update_led_colors()

        var voc_color = self.get_led_color(DisplaySensorDriver.SENSOR_VOC)
        var nox_color = self.get_led_color(DisplaySensorDriver.SENSOR_NOX)
        var voc_nox_combined = voc_color
        if nox_color > voc_color
            voc_nox_combined = nox_color
        end

        self.setledstate(1, self.get_led_color(DisplaySensorDriver.SENSOR_CO2))
        self.setledstate(2, self.get_led_color(DisplaySensorDriver.SENSOR_PMS))
        self.setledstate(3, voc_nox_combined)
    end

    # Displays all sensor values on the screen.
    def show_all_sensor_values()
        var y = 0
        var command = "backlog "
        command += "displaytext [C1B0y" + str(self.liney[y])   + "f5s1]" + "    CO2: " + string.format("%4d", self.co2_value) + "   ;"
        command += "displaytext [C1B0y" + str(self.liney[y+1]) + "f5s1]" + " PM 2.5: " + string.format("%4d", self.pm25_value) + "   ;"
        command += "displaytext [C1B0y" + str(self.liney[y+2]) + "f5s1]" + "VOC/NOx: " + string.format("%3d", self.voc_index_value) + " / " + string.format("%3d", self.nox_index_value)  + "   ;"
        command += "displaytext [C1B0y" + str(self.liney[y+3]) + "f5s1]" + "  Atm P: " + str(self.aht_hpa) + " hPa   ;"
        command += "displaytext [C1B0y" + str(self.liney[y+4]) + "f5s1]" + "Temp/RH: " + str(self.aht_temp) + "" + self.temp_scale_st + " /" +  str(self.aht_hum) + "%   "
        tasmota.cmd(command)
    end

    # Returns display name for a sensor type
    def get_sensor_name(sensor_type)
        if sensor_type == DisplaySensorDriver.SENSOR_CO2
            return "CO2"
        elif sensor_type == DisplaySensorDriver.SENSOR_PMS
            return "PM2"
        elif sensor_type == DisplaySensorDriver.SENSOR_VOC
            return "VOC"
        elif sensor_type == DisplaySensorDriver.SENSOR_NOX
            return "NOx"
        end
        return ""
    end

    # Shows a high pollution warning on the display for a specific sensor.
    def show_warning(sensor_type)
        if DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.displaysensorinfo)
            var sensorst = self.get_sensor_name(sensor_type)
            tasmota.cmd("backlog displaytext [zx0y0f2s2p-9] _; displaytext [x0y2f2s1]  HIGH; displaytext [x18y28f2s2]" + sensorst + ";")
            self.tick = -5
        end
    end

    # Triggers alerts (buzzer and visual warnings) if pollution levels are high.
    # Also resets last levels when pollution drops.
    def raise_alert()
        for sensor_type: self.sensor_types
            var cfg = self.sensors.find(sensor_type)
            if cfg == nil
                continue
            end

            var color = cfg['led_color']
            var last_level = cfg['last_level']

            # Trigger alert if level increased above threshold
            if color > 2 && color > last_level
                if self.is_level_well_above_setlimits(sensor_type)
                    self.buzzer(color)
                    self.show_warning(sensor_type)
                    cfg['last_level'] = color
                    cfg['change_count'] = 0
                end
            end

            # Reset last level if color dropped
            if cfg['last_level'] > color
                cfg['last_level'] = color
            end
        end
    end

    def _get_sensor_display_info(index)
        if index == 0
            return { "title": "CO2 ppm", "value": string.format("%4d", self.co2_value) }
        elif index == 1
            return { "title": "PM 2.5", "value": string.format("%4d", self.pm25_value) }
        elif index == 2
            return { "title": "VOC Index", "value": string.format("%3d", self.voc_index_value) }
        elif index == 3
            return { "title": "NOx Index", "value": string.format("%3d", self.nox_index_value) }
        elif index == 4
            return { "title": "Degrees " + self.temp_scale_st, "value": str(self.aht_temp) }
        elif index == 5
            return { "title": "Rel Humidity", "value": str(self.aht_hum) }
        end
        return nil
    end

    # Scrolls through individual sensor values on the display.
    def scroll_sensor_values()
        var header = ""

        if self.show_sensor_indx > 5
            self.show_sensor_indx = 0
        end

        if self.display_mode == 2
            self.show_sensor_indx = 1
        end 
        
        var display_info = nil
        if self.display_mode < 2
             display_info = self._get_sensor_display_info(self.show_sensor_indx)
        elif self.show_sensor_indx == 1
             display_info = self._get_sensor_display_info(1)
        end

        if display_info != nil
            tasmota.cmd("displaytext [x0y0f2s2]" + header + str(display_info['value']) + "    ")
            tasmota.cmd("displaytext [x0y48f1s1]      " + display_info['title'] + "       ")
        end

        self.show_sensor_indx += 1
    end

    # Computes an overall air quality score based on the highest pollution level.
    def compute_air_quality()
        var aq = 0
        for sensor_type: self.sensor_types
            var color = self.get_led_color(sensor_type)
            if color > aq
                aq = color
            end
        end
        self.air_quality = aq
    end

    # Appends a JSON payload with sensor data to the Tasmota response.
    def json_append()
        import string
        self.compute_air_quality()

        var aq = self.air_quality
        if aq == nil 
            aq = 0 
        end

        var co2 = self.co2_value
        if co2 == nil 
            co2 = -1 
        end
        
        var pm1 = self.pm1_value
        if pm1 == nil 
            pm1 = 0 
        end
        
        var pm25 = self.pm25_value
        if pm25 == nil 
            pm25 = -1 
        end

        var pm10 = self.pm10_value
        if pm10 == nil 
            pm10 = 0 
        end

        var voc = self.voc_index_value
        if voc == nil 
            voc = -1 
        end

        var nox = self.nox_index_value
        if nox == nil 
            nox = -1 
        end

        var msg = string.format(
            ",\"CAQM\":{\"AirQuality\":%i,\"CarbonDioxide\":%i,\"PM1\":%i,\"PM2.5\":%i,\"PM10\":%i,\"TVOC\":%i,\"NO2\":%i}",
            aq, co2, pm1, pm25, pm10, voc, nox
        )
        tasmota.response_append(msg)
    end




    # Displays a spinning timer animation on the screen.
    def show_timer_dots()
        var sym = ["|", "/", "-", "\\", "|", "/", "-", "\\", "|", "/", "-", "\\", "|", "/", "-", "\\", "|", "/", "-", "\\", "|", "/", "-", "\\", "|", "/", "-", "\\", "|", "/", "-", "\\", "|", "/", "-", "\\", "|", "/", "-", "\\"]
        tasmota.cmd("displaytext [x63y52f1s1]" + sym[self.tick])
    end

    # Handles the display of sensor values based on the current display mode.
    def display_sensor_values()
        if DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.displaysensorinfo)
            if self.display_mode_previous != self.display_mode
                tasmota.cmd("displaytext [zC1B0] ")
                tasmota.cmd("displaytext [zC1B0] ")
                self.display_mode_previous = self.display_mode
            end
            if self.display_mode == 0
                self.show_all_sensor_values()
            elif self.display_mode == 1
                self.scroll_sensor_values()
            else 
                self.scroll_sensor_values()                
            end
        end 
    end

    # Displays a banner with two lines of text on the screen.
    def ShowBanner(line1, line2)
        tasmota.cmd("DisplayText [O]")
        tasmota.cmd("DisplayText [z]")
        tasmota.cmd("backlog displaytext [zx0y18f1s1]" + line1 + "; displaytext [x0y32f1s1]" + line2 +";")
        tasmota.cmd("backlog Delay 5; DisplayText [z]")
    end

    # Increments counters for sensors with high readings to manage alert frequency.
    def check_tcount()
        for sensor_type: self.sensor_types
            var cfg = self.sensors.find(sensor_type)
            if cfg != nil
                var color = cfg['led_color']
                var count = cfg['change_count']
                var last = cfg['last_level']
                if color > 2 && count < self.level_change_count_limit && last != color
                    cfg['change_count'] = count + 1
                end
            end
        end
    end

    def _handle_startup_tasks()
        if self.tick == 5
            if !self.onceonstartup1 && !DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.startup_complete)
                tasmota.cmd("displaytext [zC1B0] ")
                tasmota.cmd("displaytext [zC1B0] ")
                self.onceonstartup1 = true
                self.autorestart_hrs = DisplaySensorDriver.get_sys_mem_as_number(11)

                if self.autorestart_hrs > 0
                    self.ShowBanner("   Auto Restart", "   In " + str(self.autorestart_hrs) + " Hours")
                end
                
                if self.get_reboot_after_mins() < self.time_to_cold_start
                    log("warm start")
                    self.cold_start = false
                else
                    log("cold start")
                    self.cold_start = true
                end 

                self.set_tempoffset()
                self.onceonstartup2 = true
                DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, true)
                DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.startup_complete, true)
            end
        end 
    end

    def _process_tick_tasks(tick)
        if tick == 1
            if !self.onceonstartup1 && !DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.startup_complete)
                DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, false)
                var id = self.get_device_id()    
                tasmota.cmd("Backlog displaymode 0; displaytext [zx0y0f2s2]AQM9; displaytext [x0y54f5s1]SN:" + id + " v" + DisplaySensorDriver.Product_version + ";")
            end 
        end

        if !self.onceonstartup2 && self.onceonstartup1
            self.show_timer_dots()
        end

        if tick % 6 == 0 
            self.load_sensor_values()
        end

        if tick % 10 == 0 
            self.raise_alert()
            self.shineleds()
            self.update_buzzer_and_display_mode_state() 
            self.set_temp_scale()
        end

        if  self.tick == -1
            if DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.displaysensorinfo)
                tasmota.cmd("displaytext [zC1B0] ")
                tasmota.cmd("displaytext [zC1B0] ")
                self.clear_screen_after_warning = true
            end
        end

        if self.tick == 5 && self.clear_screen_after_warning
            if DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.displaysensorinfo)
                tasmota.cmd("displaytext [zC1B0] ")
                tasmota.cmd("displaytext [zC1B0] ")
            end
            self.clear_screen_after_warning = false
        end

        if  self.tick >= 0 && self.tick % 5 == 0
            if DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.displaysensorinfo)

                self.display_sensor_values()

            end
        end

        if tick >= 24
            if !self.onceonstartup2
                tasmota.cmd("displaytext [zC1B0] ")
                tasmota.cmd("displaytext [zC1B0] ")
                DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, true)
                self.onceonstartup2 = true
            end
            
            if self.autorestart_hrs > 0
                self.current_uptime_hrs = self.get_uptime_hrs()
                if self.current_uptime_hrs >= self.autorestart_hrs  
                    self.ShowBanner("   Auto Restart", "   Rebooting...")
                    tasmota.cmd("backlog delay 5; restart 1;")
                end
            end
        end

        if tick >= 60
            self.set_tempoffset()
            return true # reset tick
        end
        return false
    end

    # Main loop executed every second to update sensor data, display, and alerts.
    def every_second()
        self.check_tcount()

        self._handle_startup_tasks()

        self.tick += 1

        if self._process_tick_tasks(self.tick)
            self.tick = 0 
        end
    end
end


class MenuManager
    var driver_instance

    # Menu definitions stored as maps
    var menus

    # Navigation state
    var menupointer
    var inmenupointer
    var currentmenu
    var displayingmenu

    # Device state
    var buzz_active
    var wificonfig
    var wifi_state
    var hostname
    var ipv4
    var subnet
    var gateway
    var dns1
    var dns2
    var mac
    var connapssid
    var uptimest
    var displayoff
    var dialog_displayed
    var device_id

    # LED strip reference (shared)
    var led_strip

    # ============================================================
    # Static Constants - Menu Indices
    # ============================================================
    static var MENU_MAIN = 0
    static var MENU_BUZZER_DIALOG = 1
    static var MENU_WIFI = 2
    static var MENU_CO2_CALIBRATION = 3
    static var MENU_SETTINGS = 4
    static var MENU_WIFI_ONOFF = 5
    static var MENU_WIFI_LOCALAP = 6
    static var MENU_CALIBRATION_DONE = 7
    static var MENU_WIFI_RESET = 8
    static var MENU_NETINFO_SSID = 9
    static var MENU_NETINFO_HOSTNAME = 10
    static var MENU_NETINFO_MAC = 11
    static var MENU_NETINFO_DNS = 12
    static var MENU_CONFIRM_WIFI = 13
    static var MENU_CONFIRM_LOCALAP = 14
    static var MENU_CONFIRM_BUZZER = 15
    static var MENU_ABOUT = 16
    static var MENU_DISPLAY_MODE = 17
    static var MENU_SENSOR = 18
    static var MENU_CONFIRM_DISPLAY = 19
    static var MENU_PMS_POLL = 20
    static var MENU_CONFIRM_PMS = 21
    static var MENU_LED_BUZZER = 22
    static var MENU_LED_BRIGHTNESS = 23
    static var MENU_CONFIRM_LED = 24
    static var MENU_TEMP_SCALE = 25
    static var MENU_CONFIRM_TEMP = 26

    # ============================================================
    # Static Constants - Option Definitions [menu_index, item_index]
    # ============================================================
    static var OPT_WIFI_INFO = [2, 0]
    static var OPT_WIFI_ONOFF = [5, 2]
    static var OPT_WIFI_LOCALAP = [6, 3]
    static var OPT_WIFI_RESET = [8, 3]
    static var OPT_CO2_CALIBRATE = [3, 3]
    static var OPT_BUZZER_TOGGLE = [1, 2]
    static var OPT_PMS_1MIN = [20, 1]
    static var OPT_PMS_5MIN = [20, 2]
    static var OPT_PMS_CONT = [20, 3]
    static var OPT_LED_100 = [23, 0]
    static var OPT_LED_50 = [23, 1]
    static var OPT_LED_30 = [23, 2]
    static var OPT_TEMP_C = [25, 1]
    static var OPT_TEMP_F = [25, 2]
    static var OPT_DISPLAY_ALL = [17, 0]
    static var OPT_DISPLAY_SCROLL = [17, 1]
    static var OPT_DISPLAY_PM = [17, 2]

    # ============================================================
    # Initialization
    # ============================================================
    def init(driver)
        self.driver_instance = driver
        self._init_state()
        self._init_menus()
        self._init_led_strip()
        self.update_general_info()
        self._set_menu_item(MenuManager.MENU_ABOUT, 2, "Device ID: " + self.device_id)
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, true)
    end

    def _init_state()
        self.menupointer = 0
        self.inmenupointer = 0
        self.currentmenu = nil
        self.displayingmenu = false
        self.buzz_active = true
        self.wificonfig = -1
        self.wifi_state = true
        self.hostname = ""
        self.ipv4 = ""
        self.subnet = ""
        self.gateway = ""
        self.dns1 = ""
        self.dns2 = ""
        self.mac = ""
        self.connapssid = ""
        self.uptimest = ""
        self.displayoff = false
        self.dialog_displayed = false
        self.device_id = "000000"
    end

    def _init_led_strip()
        self.led_strip = Leds(3, 18, Leds.WS2812_GRB)
    end

    def _init_menus()
        # Menu structure: each menu is a map with named keys
        # 'first': first selectable item index (0-based within items)
        # 'submenu': true if has submenus
        # 'subs': array of submenu indices (-1 = no submenu)
        # 'parent': parent menu index
        # 'items': array of menu item strings
        self.menus = [
            # 0: Main Menu
            {'first': 0, 'submenu': true, 'subs': [4, 18, 16, 0], 'parent': 0,
             'items': ["1. General", "2. Sensor", "3. About", "< Back"]},
            # 1: Buzzer On/Off Dialog
            {'first': 2, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 4,
             'items': ["Buzzer is OFF", "", "Turn ON Buzzer", "Cancel"]},
            # 2: WiFi Menu
            {'first': 0, 'submenu': true, 'subs': [9, 5, 8, -1], 'parent': 4,
             'items': ["1. WiFi Info", "2. WiFi On/Off", "3. Reset WiFi", "< Back"]},
            # 3: CO2 Calibration Dialog
            {'first': 3, 'submenu': false, 'subs': [-1, -1, -1, 6], 'parent': 18,
             'items': ["Place the device in", "outside air for 10mins", "", "Calibrate", "Cancel"]},
            # 4: Settings Menu
            {'first': 0, 'submenu': true, 'subs': [22, 17, 25, 2], 'parent': 0,
             'items': ["1. LED/Buzzer", "2. Display Mode", "3. Temp Scale", "4. Wifi", "< Back"]},
            # 5: WiFi On/Off Dialog
            {'first': 2, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 2,
             'items': ["WiFi is OFF", "", "Turn ON WiFi", "Cancel"]},
            # 6: Local AP Dialog
            {'first': 3, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 2,
             'items': ["Local AP will start", "whenever WiFi is", "not connected.", "Start Now", "< Back"]},
            # 7: Calibration Complete Dialog
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 18,
             'items': ["", "      Calibration", "       Completed", "", "< Back"]},
            # 8: WiFi Reset Dialog
            {'first': 3, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 2,
             'items': ["Device will restart", "Connect to:", "tasmota-3B7740-5952", "Reset WiFi", "Cancel"]},
            # 9: WiFi Info - SSID
            {'first': 3, 'submenu': true, 'subs': [-1, -1, -1, 10], 'parent': 2,
             'items': ["WiFi Status: ", "Not Connected / Connected to:", "tasmota-3B7740-5952", "Next >", "< Back"]},
            # 10: WiFi Info - Hostname/IP
            {'first': 3, 'submenu': true, 'subs': [-1, -1, -1, 11], 'parent': 9,
             'items': ["Hostname:", "tasmota-3B7740-5952", "IP:255.255.255.255", "Next >", "< Back"]},
            # 11: WiFi Info - MAC/Gateway/Subnet
            {'first': 3, 'submenu': true, 'subs': [-1, -1, -1, 12], 'parent': 10,
             'items': ["MAC:08:B6:1F:3B:77:40", "GW:255.255.255.255", "Sub:255.255.255.255", "Next >", "< Back"]},
            # 12: WiFi Info - DNS
            {'first': 3, 'submenu': true, 'subs': [-1, -1, -1, 11], 'parent': 2,
             'items': ["DNS1 :255.255.255.255", "DNS2 :255.255.255.255", "", "< Back", "OK"]},
            # 13: WiFi On/Off Confirmation
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 2,
             'items': ["", "        WiFi", "     Turned ", "", "OK"]},
            # 14: Local AP Confirmation
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 2,
             'items': ["", "Local AP", "Connect to network:", "", "OK"]},
            # 15: Buzzer On/Off Confirmation
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 4,
             'items': ["", "      Buzzer", "     Turned ", "", "OK"]},
            # 16: About Page
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 0,
             'items': ["CLARATECH", "AQM9 v1.0", "", "", "< Back"]},
            # 17: Display Mode Menu
            {'first': 0, 'submenu': true, 'subs': [-1, -1, -1, -1], 'parent': 4,
             'items': ["1. Mode: All in one", "2. Mode: Auto Scroll", "3. Mode: PM2.5 Only", "< Back"]},
            # 18: Sensor Menu
            {'first': 0, 'submenu': true, 'subs': [3, 20, -1, -1], 'parent': 0,
             'items': ["1. CO2 Calibration", "2. PMS poll time", "< Back"]},
            # 19: Display Mode Set Confirmation
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 17,
             'items': ["", "   Display Mode", "", "    Set ", "OK"]},
            # 20: PMS Poll Time Menu
            {'first': 1, 'submenu': true, 'subs': [3, -1, -1, -1], 'parent': 0,
             'items': ["PMS Poll Time", "1. Every minute", "2. Every 5 minutes", "3. Continous Poll", "< Back"]},
            # 21: PMS Poll Time Set Confirmation
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 18,
             'items': ["", "    PMS Poll time", "       Set", "", "< Back"]},
            # 22: LED/Buzzer Menu
            {'first': 0, 'submenu': true, 'subs': [23, 1, -1, -1], 'parent': 0,
             'items': ["1. LED Brightness", "2. Buzzer ON/OFF", "< Back"]},
            # 23: LED Brightness Menu
            {'first': 0, 'submenu': true, 'subs': [-1, -1, -1, -1], 'parent': 22,
             'items': ["1. Brightness 100%", "2. Brightness 50%", "3. Brightness 30%", "< Back"]},
            # 24: LED Brightness Set Confirmation
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 23,
             'items': ["", "   LED Brightness", "       Set", "", "< Back"]},
            # 25: Temperature Scale Menu
            {'first': 1, 'submenu': true, 'subs': [-1, -1, -1, -1], 'parent': 4,
             'items': ["Temp Scale", "1. Celsius", "2. Fahrenheit", "< Back"]},
            # 26: Temperature Scale Set Confirmation
            {'first': 4, 'submenu': false, 'subs': [-1, -1, -1, -1], 'parent': 25,
             'items': ["", "     Temp Scale", "       Set", "", "< Back"]}
        ]
    end

    # ============================================================
    # Driver Control
    # ============================================================
    def start_driver()
        tasmota.add_driver(self.driver_instance)
    end

    def stop_driver()
        tasmota.remove_driver(self.driver_instance)
    end

    # ============================================================
    # Menu Helper Methods
    # ============================================================
    def _get_menu(index)
        return self.menus[index]
    end

    def _get_menu_items(menu)
        return menu['items']
    end

    def _get_menu_first(menu)
        return menu['first']
    end

    def _get_menu_parent(menu)
        return menu['parent']
    end

    def _get_menu_subs(menu)
        return menu['subs']
    end

    def _has_submenu(menu)
        return menu['submenu']
    end

    def _set_menu_item(menu_index, item_index, value)
        self.menus[menu_index]['items'][item_index] = value
    end

    def _item_count(menu)
        return size(menu['items'])
    end

    # ============================================================
    # State Update Methods
    # ============================================================
    def update_wifi_state()
        var wifist = tasmota.cmd("wifi")["Wifi"]
        var statst = tasmota.cmd("status 11")["StatusSTS"]
        self.wifi_state = (wifist == "ON")

        self.connapssid = ""
        var wifi_info = statst.find("Wifi")
        if wifi_info != nil && wifi_info["BSSId"] != ""
            self.connapssid = wifi_info["SSId"]
        end
    end

    def update_wificonfig()
        var wc = tasmota.cmd("wificonfig").find("WifiConfig")
        if wc == nil
            self.wificonfig = -1
        elif wc.find("2") != nil
            self.wificonfig = 2
        elif wc.find("4") != nil
            self.wificonfig = 4
        else
            self.wificonfig = -1
        end
    end

    def update_network_info()
        var networkinfo = tasmota.cmd("status 5")["StatusNET"]
        self.hostname = networkinfo["Hostname"]
        self.ipv4 = networkinfo["IPAddress"]
        self.gateway = networkinfo["Gateway"]
        self.subnet = networkinfo["Subnetmask"]
        self.dns1 = networkinfo["DNSServer1"]
        self.dns2 = networkinfo["DNSServer2"]
        self.mac = networkinfo["Mac"]
        self.update_wifi_state()
    end

    def update_buzzer_state()
        self.buzz_active = (tasmota.cmd("Mem16")["Mem16"] == "1")
    end

    def update_general_info()
        var ginfo = tasmota.cmd("status 1")["StatusPRM"]
        self.uptimest = ginfo["Uptime"]
        self.update_network_info()
        var devid = string.tr(self.mac, ":", "")
        self.device_id = string.split(devid, 6)[1]
    end

    # ============================================================
    # Display Methods
    # ============================================================
    def clearscreen()
        tasmota.cmd("displaytext [zC0B0] ")
        tasmota.cmd("displaytext [zC0B0] ")
    end

    def disp_dialog(*lines)
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, false)
        self.clearscreen()
        tasmota.cmd("DisplayText [O]")
        var max_lines = (size(lines) > 4) ? 4 : size(lines)
        for i: 0..max_lines - 1
            tasmota.cmd("displaytext [C1B0y" + str(self.driver_instance.liney[i]) + "f5s1]" + lines[i])
        end
        tasmota.cmd("displaytext [C1B0y" + str(self.driver_instance.liney[4]) + "f5s1]" + "< OK >")
        self.dialog_displayed = true
    end

    def dismiss_dialog()
        self.dialog_displayed = false
        self.clearscreen()
        if self.displayoff
            tasmota.cmd("DisplayText [o]")
        else
            DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, true)
        end
    end

    def _show_toggle_result(name, state)
        var state_str = state ? "ON" : "OFF"
        self.disp_dialog("", "      " + name, "   Turned " + state_str, "")
    end

    # ============================================================
    # LED Control (deduplicated)
    # ============================================================
    def leds_off()
        for i: 0..2
            self.led_strip.set_pixel_color(i, 0x000000)
        end
        self.led_strip.show()
    end

    def shine_leds(percent)
        var colors = [0xFF0000, 0x00FF00, 0x0000FF]
        for i: 0..2
            self.led_strip.set_pixel_color(i, colors[i], percent)
        end
        self.led_strip.show()
    end

    # ============================================================
    # Menu Update Handlers (extracted from update_menu)
    # ============================================================
    def _update_display_mode_menu()
        if self.menupointer != MenuManager.MENU_CONFIRM_DISPLAY
            return
        end
        var mode = number(tasmota.cmd("Mem15")["Mem15"])
        var txt = "All in one"
        if mode == 1
            txt = "Auto Scroll"
        elif mode == 2
            txt = "PM2.5 Only"
        end
        self._set_menu_item(MenuManager.MENU_CONFIRM_DISPLAY, 2, "   " + txt)
    end

    def _update_about_menu()
        if self.menupointer != MenuManager.MENU_ABOUT
            return
        end
        self.update_general_info()
        self._set_menu_item(MenuManager.MENU_ABOUT, 0, DisplaySensorDriver.Manufacturer)
        self._set_menu_item(MenuManager.MENU_ABOUT, 1, DisplaySensorDriver.Product_model + " " + DisplaySensorDriver.Product_version)
        self._set_menu_item(MenuManager.MENU_ABOUT, 3, "Uptime: " + self.uptimest)
    end

    def _update_buzzer_dialog()
        if self.menupointer != MenuManager.MENU_BUZZER_DIALOG
            return
        end
        self.update_buzzer_state()
        var state = self.buzz_active ? "ON" : "OFF"
        var action = self.buzz_active ? "OFF" : "ON"
        self._set_menu_item(MenuManager.MENU_BUZZER_DIALOG, 0, "Buzzer Status: " + state)
        self._set_menu_item(MenuManager.MENU_BUZZER_DIALOG, 2, "Turn " + action + " Buzzer")
    end

    def _update_wifi_dialogs()
        if self.menupointer == MenuManager.MENU_WIFI_ONOFF
            self.update_wifi_state()
            var state = self.wifi_state ? "ON" : "OFF"
            var action = self.wifi_state ? "OFF" : "ON"
            self._set_menu_item(MenuManager.MENU_WIFI_ONOFF, 0, "WiFi Status: " + state)
            self._set_menu_item(MenuManager.MENU_WIFI_ONOFF, 2, "Turn " + action + " WiFi")
        end

        if self.menupointer == MenuManager.MENU_CONFIRM_WIFI
            self.update_wifi_state()
            self._set_menu_item(MenuManager.MENU_CONFIRM_WIFI, 2, "     Turned " + (self.wifi_state ? "ON" : "OFF"))
        end

        if self.menupointer == MenuManager.MENU_CONFIRM_BUZZER
            self.update_buzzer_state()
            self._set_menu_item(MenuManager.MENU_CONFIRM_BUZZER, 2, "     Turned " + (self.buzz_active ? "ON" : "OFF"))
        end

        if self.menupointer == MenuManager.MENU_WIFI_LOCALAP
            self.update_wificonfig()
            self._set_menu_item(MenuManager.MENU_WIFI_LOCALAP, 3, (self.wificonfig == 2 ? "Disable" : "Start Now"))
        end

        if self.menupointer == MenuManager.MENU_CONFIRM_LOCALAP
            self.update_wificonfig()
            var enabled = (self.wificonfig == 2)
            self._set_menu_item(MenuManager.MENU_CONFIRM_LOCALAP, 0, "Local AP " + (enabled ? "Enabled" : "Disabled"))
            self._set_menu_item(MenuManager.MENU_CONFIRM_LOCALAP, 1, enabled ? "Connect to" : "")
            self._set_menu_item(MenuManager.MENU_CONFIRM_LOCALAP, 2, enabled ? self.hostname : "")
        end
    end

    def _update_network_info_pages()
        if !self._is_option_selected(MenuManager.OPT_WIFI_INFO)
            return
        end
        self.update_network_info()

        self._set_menu_item(MenuManager.MENU_NETINFO_SSID, 0, "WiFi Status:" + (self.wifi_state ? "ON" : "OFF"))
        self._set_menu_item(MenuManager.MENU_NETINFO_SSID, 1, self.connapssid != "" ? "Connected to:" : "Not Connected")
        self._set_menu_item(MenuManager.MENU_NETINFO_SSID, 2, self.connapssid)

        self._set_menu_item(MenuManager.MENU_NETINFO_HOSTNAME, 1, self.hostname)
        self._set_menu_item(MenuManager.MENU_NETINFO_HOSTNAME, 2, "IP:" + self.ipv4)

        self._set_menu_item(MenuManager.MENU_NETINFO_MAC, 0, "MAC:" + self.mac)
        self._set_menu_item(MenuManager.MENU_NETINFO_MAC, 1, "GW:" + self.gateway)
        self._set_menu_item(MenuManager.MENU_NETINFO_MAC, 2, "Sub:" + self.subnet)

        self._set_menu_item(MenuManager.MENU_NETINFO_DNS, 0, "DNS1 :" + self.dns1)
        self._set_menu_item(MenuManager.MENU_NETINFO_DNS, 1, "DNS2 :" + self.dns2)
    end

    def update_menu()
        self._update_display_mode_menu()
        self._update_about_menu()
        self._update_buzzer_dialog()
        self._update_wifi_dialogs()
        self._update_network_info_pages()
    end

    # ============================================================
    # Menu Display Methods
    # ============================================================
    def showmenu(menu)
        self.update_menu()
        self.clearscreen()
        var items = self._get_menu_items(menu)
        for i: 0..size(items) - 1
            tasmota.cmd("displaytext [C1B0y" + str(self.driver_instance.liney[i]) + "f5s1]" + items[i])
        end
    end

    def showselected(menu, indx, firstoptionindex)
        var items = self._get_menu_items(menu)
        var item_count = size(items)

        if indx == firstoptionindex && firstoptionindex != item_count - 1
            tasmota.cmd("displaytext [C1B0y" + str(self.driver_instance.liney[item_count - 1]) + "f5s1]" + items[item_count - 1])
        end
        if indx > firstoptionindex
            tasmota.cmd("displaytext [C1B0y" + str(self.driver_instance.liney[indx - 1]) + "f5s1]" + items[indx - 1])
        end
        tasmota.cmd("displaytext [C0B1y" + str(self.driver_instance.liney[indx]) + "f5s1]" + items[indx])
    end

    def showselected_reverse(menu, indx, firstoptionindex)
        var items = self._get_menu_items(menu)
        var item_count = size(items)

        if indx < item_count - 1
            tasmota.cmd("displaytext [C1B0y" + str(self.driver_instance.liney[indx + 1]) + "f5s1]" + items[indx + 1])
        end
        if indx == item_count - 1
            tasmota.cmd("displaytext [C1B0y" + str(self.driver_instance.liney[firstoptionindex]) + "f5s1]" + items[firstoptionindex])
        end
        tasmota.cmd("displaytext [C0B1y" + str(self.driver_instance.liney[indx]) + "f5s1]" + items[indx])
    end

    def _is_option_selected(option)
        return self.menupointer == option[0] && self.inmenupointer == option[1]
    end

    def show_dialog_menu(dialog_menu_index)
        self.menupointer = dialog_menu_index
        self.currentmenu = self._get_menu(self.menupointer)
        self.inmenupointer = self._get_menu_first(self.currentmenu)
        self.showmenu(self.currentmenu)
        self.showselected(self.currentmenu, self.inmenupointer, self._get_menu_first(self.currentmenu))
    end

    # ============================================================
    # Display Toggle Methods
    # ============================================================
    def DispON()
        tasmota.cmd("DisplayText [O]")
        tasmota.cmd("DisplayText [z]")
        tasmota.cmd("backlog displaytext [zx36y18f1s1]DISPLAY; displaytext [x30y32f1s1]TURNED ON;")
        tasmota.cmd("backlog Delay 5; DisplayText [z]")
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, true)
        self.displayoff = false
    end

    def DispOFF()
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, false)
        tasmota.cmd("backlog displaytext [zx28y18f1s1]TURNING OFF; displaytext [x36y32f1s1]DISPLAY...;")
        tasmota.cmd("backlog Delay 50; DisplayText [z]; DisplayText [o]")
        tasmota.cmd("backlog Delay 5; DisplayText [z]")
        self.displayoff = true
    end

    def ledsON()
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.sensor_led_on, true)
        self._show_led_message("TURNING ON")
    end

    def ledsOFF()
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.sensor_led_on, false)
        self._show_led_message("TURNING OFF")
        self.leds_off()
    end

    def _show_led_message(action)
        if self.displayoff
            tasmota.cmd("DisplayText [O]")
        end
        tasmota.cmd("DisplayText [z] ")
        tasmota.cmd("backlog displaytext [zx28y18f1s1]" + action + "; displaytext [x36y32f1s1]LEDs...;")
        tasmota.cmd("backlog Delay 5; DisplayText [z];")
        if self.displayoff
            tasmota.cmd("backlog Delay 2; DisplayText [o]")
        end
    end

    # ============================================================
    # Menu Action Handlers (extracted from process_menu_confirm_action)
    # ============================================================
    def _handle_back_navigation()
        var items = self._get_menu_items(self.currentmenu)
        if self.inmenupointer != size(items) - 1
            return false
        end

        if self.menupointer == MenuManager.MENU_MAIN
            self.exit_menu()
            return true
        end

        self.menupointer = self._get_menu_parent(self.currentmenu)
        self.currentmenu = self._get_menu(self.menupointer)
        self.inmenupointer = self._item_count(self.currentmenu) - 1
        self.showmenu(self.currentmenu)
        self.showselected(self.currentmenu, self.inmenupointer, self._get_menu_first(self.currentmenu))
        return true
    end

    def _handle_submenu_navigation()
        if !self._has_submenu(self.currentmenu)
            return false
        end

        var subs = self._get_menu_subs(self.currentmenu)
        var sub_index = subs[self.inmenupointer]
        if sub_index < 0
            return false
        end

        self.menupointer = sub_index
        self.currentmenu = self._get_menu(self.menupointer)
        self.inmenupointer = self._get_menu_first(self.currentmenu)
        self.showmenu(self.currentmenu)
        self.showselected(self.currentmenu, self.inmenupointer, self._get_menu_first(self.currentmenu))
        return true
    end

    def _handle_pms_options()
        if self._is_option_selected(MenuManager.OPT_PMS_1MIN)
            tasmota.cmd("Sensor18 60")
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_PMS)
            return true
        end
        if self._is_option_selected(MenuManager.OPT_PMS_5MIN)
            tasmota.cmd("Sensor18 300")
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_PMS)
            return true
        end
        if self._is_option_selected(MenuManager.OPT_PMS_CONT)
            tasmota.cmd("Sensor18 5")
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_PMS)
            return true
        end
        return false
    end

    def _handle_led_options()
        var brightness_map = {
            'OPT_LED_100': 100,
            'OPT_LED_50': 50,
            'OPT_LED_30': 30
        }

        if self._is_option_selected(MenuManager.OPT_LED_100)
            tasmota.cmd("MEM14 100")
            self.shine_leds(100)
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_LED)
            self.leds_off()
            return true
        end
        if self._is_option_selected(MenuManager.OPT_LED_50)
            tasmota.cmd("MEM14 50")
            self.shine_leds(50)
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_LED)
            self.leds_off()
            return true
        end
        if self._is_option_selected(MenuManager.OPT_LED_30)
            tasmota.cmd("MEM14 30")
            self.shine_leds(30)
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_LED)
            self.leds_off()
            return true
        end
        return false
    end

    def _handle_temp_options()
        if self._is_option_selected(MenuManager.OPT_TEMP_C)
            tasmota.cmd("SO8 0")
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_TEMP)
            return true
        end
        if self._is_option_selected(MenuManager.OPT_TEMP_F)
            tasmota.cmd("SO8 1")
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_TEMP)
            return true
        end
        return false
    end

    def _handle_wifi_options()
        if self._is_option_selected(MenuManager.OPT_WIFI_ONOFF)
            if self.wifi_state
                tasmota.cmd("wifi 0")
                tasmota.cmd("SetOption31 1")
            else
                tasmota.cmd("wifi 1")
                tasmota.cmd("SetOption31 0")
            end
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_WIFI)
            return true
        end

        if self._is_option_selected(MenuManager.OPT_WIFI_LOCALAP)
            if self.wificonfig != 2
                tasmota.cmd("wifi 1")
                tasmota.cmd("wificonfig 2")
            else
                tasmota.cmd("wificonfig 4")
            end
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_LOCALAP)
            return true
        end

        if self._is_option_selected(MenuManager.OPT_WIFI_RESET)
            tasmota.cmd("wifi 1")
            tasmota.cmd("backlog ssid1 1; ssid2 1; password1 1; password2 1;")
            return true
        end
        return false
    end

    def _handle_display_mode_options()
        if self._is_option_selected(MenuManager.OPT_DISPLAY_ALL)
            tasmota.cmd("mem15 0")
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_DISPLAY)
            return true
        end
        if self._is_option_selected(MenuManager.OPT_DISPLAY_SCROLL)
            tasmota.cmd("mem15 1")
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_DISPLAY)
            return true
        end
        if self._is_option_selected(MenuManager.OPT_DISPLAY_PM)
            tasmota.cmd("mem15 2")
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_DISPLAY)
            return true
        end
        return false
    end

    def _handle_buzzer_option()
        if self._is_option_selected(MenuManager.OPT_BUZZER_TOGGLE)
            tasmota.cmd("mem16 " + (self.buzz_active ? "0" : "1"))
            self.show_dialog_menu(MenuManager.MENU_CONFIRM_BUZZER)
            return true
        end
        return false
    end

    def _handle_sensor_options()
        if self._is_option_selected(MenuManager.OPT_CO2_CALIBRATE)
            tasmota.cmd("Sensor15 2")
            tasmota.cmd("Sensor15 10000")
            self.show_dialog_menu(MenuManager.MENU_CALIBRATION_DONE)
            return true
        end
        return false
    end

    def process_menu_confirm_action()
        if self._handle_back_navigation()
            return
        end
        if self._handle_submenu_navigation()
            return
        end

        # Handle specific options
        if self._handle_pms_options()
            return
        end
        if self._handle_led_options()
            return
        end
        if self._handle_temp_options()
            return
        end
        if self._handle_wifi_options()
            return
        end
        if self._handle_display_mode_options()
            return
        end
        if self._handle_buzzer_option()
            return
        end
        if self._handle_sensor_options()
            return
        end
    end

    # ============================================================
    # Menu Navigation
    # ============================================================
    def showselectedmenu(forward)
        if self.currentmenu == nil
            return
        end

        var item_count = self._item_count(self.currentmenu)
        var first = self._get_menu_first(self.currentmenu)

        if forward
            if self.inmenupointer >= item_count
                self.inmenupointer = first
            end
            self.showselected(self.currentmenu, self.inmenupointer, first)
        else
            if self.inmenupointer < first
                self.inmenupointer = item_count - 1
            end
            if self.inmenupointer >= first
                self.showselected_reverse(self.currentmenu, self.inmenupointer, first)
            end
        end
    end

    def exit_menu()
        self.clearscreen()
        self.menupointer = 0
        self.inmenupointer = -1
        tasmota.cmd("displaytext [C1B0y10f5s1] ")
        self.displayingmenu = false
        self.start_driver()
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, true)
    end

    # ============================================================
    # Quick Actions
    # ============================================================
    def buzz_toggle()
        self.update_buzzer_state()
        tasmota.cmd("Mem16 " + (self.buzz_active ? "0" : "1"))
        self._show_toggle_result("Buzzer", !self.buzz_active)
    end

    def show_ip()
        self.update_network_info()
        self.disp_dialog("", " WiFi IP:", "" + self.ipv4, "")
    end

    def _toggle_wifi()
        self.update_wifi_state()
        if self.wifi_state
            tasmota.cmd("wifi 0")
            tasmota.cmd("SetOption31 1")
        else
            tasmota.cmd("wifi 1")
            tasmota.cmd("SetOption31 0")
        end
        self._show_toggle_result("WiFi Status", !self.wifi_state)
    end

    # ============================================================
    # Button Handlers
    # ============================================================
    def Button_Menu(value, trigger, msg)
        if value == 12
            self.exit_menu()
            return
        end

        if self.dialog_displayed
            self.dismiss_dialog()
            return
        end

        if value == 10
            self._handle_menu_down()
        end

        if (value == 11 || value == 3) && self.displayingmenu
            self.process_menu_confirm_action()
        end
    end

    def _handle_menu_down()
        if !self.displayingmenu
            self._enter_menu_mode()
        end
        self.inmenupointer += 1
        self.showselectedmenu(true)
    end

    def _enter_menu_mode()
        self.stop_driver()
        self.leds_off()
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, false)
        if self.displayoff
            tasmota.cmd("DisplayText [O]")
            self.displayoff = false
        end
        self.currentmenu = self._get_menu(self.menupointer)
        self.showmenu(self.currentmenu)
        self.displayingmenu = true
        self.inmenupointer = self._get_menu_first(self.currentmenu) - 1
    end

    def Button_Options(value, trigger, msg)
        if self.dialog_displayed
            self.dismiss_dialog()
            return
        end

        if value == 12 && self.displayingmenu
            self.exit_menu()
            return
        end

        if value == 3 && !self.displayingmenu
            self._toggle_wifi()
            return
        end

        if self.displayingmenu
            self._handle_options_in_menu(value)
        else
            self._handle_options_quick(value)
        end
    end

    def _handle_options_in_menu(value)
        if value == 11 || value == 3
            self.process_menu_confirm_action()
        end
        if value == 10
            self.inmenupointer -= 1
            self.showselectedmenu(false)
        end
    end

    def _handle_options_quick(value)
        if value == 10
            if self.displayoff
                self.DispON()
            else
                self.DispOFF()
            end
        elif value == 11
            if DisplaySensorDriver.get_sys_var_bool(DisplaySensorDriver.sensor_led_on)
                self.ledsOFF()
            else
                self.ledsON()
            end
        elif value == 12
            self.show_ip()
        elif value == 13
            self.buzz_toggle()
        end
    end
end


# Global variables for menu and device state
var loadwaitcount = 0
var bootclearscreen = true

# Tasmota command to get sensor data in JSON format.
def caqm(aaa, bbb, ccc)
    var sensors = json.load(tasmota.read_sensors())
    tasmota.resp_cmnd(str(sensors['CAQM']))
end

# Tasmota command to enable or disable automatic temperature offset.
def autotempoffset(cmd, idx, payload, payload_json)
    var val = 0 
    if size(payload) > 0
        if number(payload) == 0
            tasmota.cmd("MEM12 0")
            print("Auto Temp Offset turned OFF")
            tasmota.cmd("tempoffset 0")
        elif number(payload) == 1
            tasmota.cmd("MEM12 1")
            print("Auto Temp Offset turned ON")
        end
    else
        val = DisplaySensorDriver.get_sys_mem_as_number(12)
        if number(val) > 0
            log("Automatic temp offset is ON")
        else
            log("Automatic temp offset is OFF")
        end 
    end
    tasmota.resp_cmnd_done()
end

# Tasmota command to set an auto-restart interval in hours.
def autorestart(cmd, idx, payload, payload_json)
    var val = 0
    if size(payload) > 0
        payload = number(payload)
        if payload == 0
            tasmota.cmd("MEM11 0")
            log("AutoRestart turned OFF")
        elif payload >= 1
            if payload > 23
                payload = 23
            end
            tasmota.cmd("MEM11 " + str(payload))
            log("AutoRestart ON, interval " + str(payload) + " hours")
            log("Device will reboot now...")
            tasmota.cmd("backlog delay 5; restart 1;")
        end
    else
        val = DisplaySensorDriver.get_sys_mem_as_number(11)
        if number(val) > 0
            log("AutoRestart is ON, interval " + str(val) + " hours")
        else
            log("AutoRestart is OFF")
        end 
    end
    tasmota.resp_cmnd_done()
end

var driver = DisplaySensorDriver()
var menu = MenuManager(driver)

# Displays a loading animation on the screen.
var dotst = ">"
def showloading3()
    if loadwaitcount < 16
        tasmota.cmd("displaytext [x9y34f1s1]" + dotst)
        dotst = dotst + ">"
    end 
    loadwaitcount = loadwaitcount + 1
    if loadwaitcount > 17
        DisplaySensorDriver.set_sys_var_bool(DisplaySensorDriver.displaysensorinfo, true)
        bootclearscreen = true
        tasmota.remove_cron("showloading3")
    end
end

def showloading2()
    tasmota.cmd("displaytext [x0y34f1s1]~5b")
    tasmota.cmd("displaytext [x122y34f1s1]~5d")
    tasmota.add_cron("*/4 * * * * *", showloading3, "showloading3")
end

def showloading()
    tasmota.cmd("Backlog displaytext [zy0f1s1]   Initializing; displaytext [y18f1s1]      Sensors;")
end 

def Button1_Handler(value, trigger, msg)
    menu.Button_Options(value, trigger, msg)
end

def Button2_Handler(value, trigger, msg)
    menu.Button_Menu(value, trigger, msg)
end

# Add Tasmota commands
tasmota.add_cmd('caqm', caqm)
tasmota.add_cmd('autotemp', autotempoffset)
tasmota.add_cmd('autorestart', autorestart)

# Initial Tasmota settings
tasmota.cmd("humoffset 5")
tasmota.cmd("SerialLog 0")
tasmota.cmd("var14 0")

var tmpolltime = number(tasmota.cmd("Mem13")['Mem13'])
if tmpolltime != nil && tmpolltime > 0
    tasmota.cmd("tmpoll " + str(tmpolltime))
end

# Add rules for button press events.
tasmota.add_rule("button1#state", Button1_Handler)
tasmota.add_rule("button2#state", Button2_Handler)

# Start the driver
tasmota.add_driver(driver)