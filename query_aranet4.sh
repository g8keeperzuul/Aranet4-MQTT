#!/bin/bash
#
# Usage:
#	$0 <MAC> <sensor-name>
#
# Description:
# This script will 
# + first announce the various sensors available on Aranet4 (temp, humidity, etc) to Home Assistant via MQTT discovery
# + send an availability "online" message to announce to Home Assistant the sensor is working; 
#   in the event of the sensor or script not functioning, the MQTT last will message will automatically set availability to "offline"
# + make Aranet inquiries (via Aranet4-Python project) and parse the response into an MQTT sensor state payload which will be published; 
#   it will do this forever, spacing each inquiry by REFRESH_RATE
#   
# Prerequisites:
#   Aranet4 sensor must be bluetooth paired to this host
#   Aranet4-Python project installed into virtualenv; https://github.com/Anrijs/Aranet4-Python
#   MQTT Mosquitto broker running at specified location
#   Mosquitto client programs available on path; apt install mosquitto-clients
#   Create directory /var/run/aranet4-daemon/ writable by user that will be used to run this script (see $PID_FILE)
#  	(this pidfile isn't strictly necessary if managed as a systemd service)

if [[ -z "$1" ]] || [[ -z "$2" ]]; then 
	echo "Usage: $0 <MAC> <sensor-name>"
	echo "To be used with Aranet4 CO2 sensor that has already been bluetooth paired to host."
	echo "Example: $0 EF:BE:2D:BA:DD:A5 aranet4-dda5"
    exit 1
fi

#SENSOR_NAME="aranet4-dda5"
#MAC="EF:BE:2D:BA:DD:A5"

MAC="$1"
SENSOR_NAME="$2"

source query_aranet4.properties

MOSQUITTO_CLIENT_ID=${SENSOR_NAME}

if [ ! -f "${ARANETCTL_DIR}/aranetctl" ]; then
    echo "aranetctl not found"
    exit 2
fi

if [ -z "$(which mosquitto_pub)" ]; then
    echo "mosquitto_pub not found"
    exit 3
fi

if [ ! -d "${PID_DIR}" ]; then
    echo "Directory must exist: ${PID_DIR}"
    exit 4
fi

# -----------------------------------------------------------------------------
# TOPICS
#   Discoverability Topic:  <HA_prefix>/<component>/[<node_id>/]<unique_id>/config
#   Availability Topic:     <HA_prefix>/<component>/[<node_id>/]<unique_id>/availability
#   State Topic:            <HA_prefix>/<component>/[<node_id>/]<device_id>/state  (where state payload contains multiple sensor readings from single device)
# where:
#   HA_prefix   =   homeassistant
#   component   =   devices supported by MQTT discovery (ie sensor, binary_sensor, etc): https://www.home-assistant.io/docs/mqtt/discovery/
#   node_id     =   anything; not used by HA; allows components to be grouped
#   unique_id   =   unique ID that identifies specific component (that may be part of a multifunctional device); combination of device ID + sensor ID
#   device_id   =   ID that identifies a device which may have many components/sensors

state_topic="homeassistant/sensor/environmental/${SENSOR_NAME}/state"
avail_topic="homeassistant/sensor/environmental/${SENSOR_NAME}/availability"

# -----------------------------------------------------------------------------
# DISCOVERY MESSAGE
#
# DEVICE_CLASS
#   https://developers.home-assistant.io/docs/core/entity/sensor#available-device-classes
#
# STATE_CLASS
#   https://developers.home-assistant.io/docs/core/entity/sensor#available-state-classes
#
# EXPIRE_AFTER
#   sensor will revert to "unavailable" after 'expire_after' seconds
#
# FORCE_UPDATE
#   forces HA to log the sensor value even if it is unachanged since the last update; adds load onto HA but adds datapoints to graphs
#
# AVAILABILITY_TOPIC
#   availability_topic allows you put the sensor offline or online. Online will only work if there is a non-expired sensor
#   reading available (otherwise it cannot be forced online).
#   availability_topic <-- online | offline
#
# DEVICE
#   several sensors that have the same device will be shown as a single device with multiple entities in HA
#
# NAME
#   Display name. Should be unique so that it can be easily identified in the UI. 
#   It can be overridden by configuration.yaml/customize:
#   This name is used to generate the entity_id (which appears cannot be set as part of this discovery config)
#
# ICON
#   From https://materialdesignicons.com/
#
# STATE_TOPIC
#   Topic where sensor updates are published. Message may have many attributes for all the sensors on the device.
#
# VALUE_TEMPLATE    
#   Extracts value from JSON message that is published to STATE_TOPIC.
#   https://jinja.palletsprojects.com/en/latest/templates/#
#   https://www.home-assistant.io/integrations/template
#   each value will be treated as a separate unique sensor

# Publish discovery message for each separate sensor available in the device

pidfile="${PID_DIR}/${SENSOR_NAME}.pid"
echo "${SENSOR_NAME} PID $$ written to ${pidfile}"
echo $$ > ${pidfile}

echo "Publishing discovery messages..."

disc_temp_topic="homeassistant/sensor/environmental/${SENSOR_NAME}_temperature/config"
disc_temp_cfg="{\"device_class\":\"temperature\",\"unit_of_measurement\":\"°C\",\"state_class\":\"measurement\",\"force_update\":false,\"availability_topic\":\"${avail_topic}\",\"unique_id\":\"${SENSOR_NAME}_temperature\",\"device\":{\"name\": \"${SENSOR_NAME}\", \"identifiers\": \"${MAC}\"},\"name\":\"${SENSOR_NAME} temperature\",\"icon\":\"mdi:home-thermometer\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.temperature }}\"}"
mosquitto_pub -q 1 -r -i $MOSQUITTO_CLIENT_ID -h $MOSQUITTO_HOST -p $MOSQUITTO_PORT -u $MOSQUITTO_USER -P $MOSQUITTO_PASS -t "${disc_temp_topic}" -m "${disc_temp_cfg}"
echo "  temperature"

disc_humidity_topic="homeassistant/sensor/environmental/${SENSOR_NAME}_humidity/config"
disc_humidity_cfg="{\"device_class\":\"humidity\",\"unit_of_measurement\":\"%\",\"state_class\":\"measurement\",\"force_update\":false,\"availability_topic\":\"${avail_topic}\",\"unique_id\":\"${SENSOR_NAME}_humidity\",\"device\":{\"name\": \"${SENSOR_NAME}\", \"identifiers\": \"${MAC}\"},\"name\":\"${SENSOR_NAME} humidity\",\"icon\":\"mdi:water-percent\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.humidity }}\"}"
mosquitto_pub -q 1 -r -i $MOSQUITTO_CLIENT_ID -h $MOSQUITTO_HOST -p $MOSQUITTO_PORT -u $MOSQUITTO_USER -P $MOSQUITTO_PASS -t "${disc_humidity_topic}" -m "${disc_humidity_cfg}"
echo "  humidity"

disc_pressure_topic="homeassistant/sensor/environmental/${SENSOR_NAME}_pressure/config"
disc_pressure_cfg="{\"device_class\":\"pressure\",\"unit_of_measurement\":\"hPa\",\"state_class\":\"measurement\",\"force_update\":false,\"availability_topic\":\"${avail_topic}\",\"unique_id\":\"${SENSOR_NAME}_pressure\",\"device\":{\"name\": \"${SENSOR_NAME}\", \"identifiers\": \"${MAC}\"},\"name\":\"${SENSOR_NAME} pressure\",\"icon\":\"mdi:gauge\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.pressure }}\"}"
mosquitto_pub -q 1 -r -i $MOSQUITTO_CLIENT_ID -h $MOSQUITTO_HOST -p $MOSQUITTO_PORT -u $MOSQUITTO_USER -P $MOSQUITTO_PASS -t "${disc_pressure_topic}" -m "${disc_pressure_cfg}"
echo "  pressure"

disc_co2_topic="homeassistant/sensor/environmental/${SENSOR_NAME}_carbon_dioxide/config"
disc_co2_cfg="{\"device_class\":\"carbon_dioxide\",\"unit_of_measurement\":\"ppm\",\"state_class\":\"measurement\",\"force_update\":false,\"availability_topic\":\"${avail_topic}\",\"unique_id\":\"${SENSOR_NAME}_carbon_dioxide\",\"device\":{\"name\": \"${SENSOR_NAME}\", \"identifiers\": \"${MAC}\"},\"name\":\"${SENSOR_NAME} carbon_dioxide\",\"icon\":\"mdi:molecule-co2\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.carbon_dioxide }}\"}"
mosquitto_pub -q 1 -r -i $MOSQUITTO_CLIENT_ID -h $MOSQUITTO_HOST -p $MOSQUITTO_PORT -u $MOSQUITTO_USER -P $MOSQUITTO_PASS -t "${disc_co2_topic}" -m "${disc_co2_cfg}"
echo "  carbon dioxide"

disc_battery_topic="homeassistant/sensor/environmental/${SENSOR_NAME}_battery/config"
disc_battery_cfg="{\"device_class\":\"battery\",\"unit_of_measurement\":\"%\",\"state_class\":\"measurement\",\"entity_category\":\"diagnostic\",\"force_update\":false,\"availability_topic\":\"${avail_topic}\",\"unique_id\":\"${SENSOR_NAME}_battery\",\"device\":{\"name\": \"${SENSOR_NAME}\", \"identifiers\": \"${MAC}\"},\"name\":\"${SENSOR_NAME} battery\",\"icon\":\"mdi:battery-50-bluetooth\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.battery }}\"}"
mosquitto_pub -q 1 -r -i $MOSQUITTO_CLIENT_ID -h $MOSQUITTO_HOST -p $MOSQUITTO_PORT -u $MOSQUITTO_USER -P $MOSQUITTO_PASS -t "${disc_battery_topic}" -m "${disc_battery_cfg}"
echo "  battery"

# -----------------------------------------------------------------------------
# Publish ONLINE availability message
# Last-will-and-testament (LWT) is included with every update so in event of dropped session, availability will be automatically set to OFFLINE by broker
# BUT this only happens if mosquitto_pub is interrupted
mosquitto_pub -q 1 -r -i $MOSQUITTO_CLIENT_ID -h $MOSQUITTO_HOST -p $MOSQUITTO_PORT -u $MOSQUITTO_USER -P $MOSQUITTO_PASS -t "${avail_topic}" -m "online"
echo -e "\nPublished ${SENSOR_NAME} online"

# -----------------------------------------------------------------------------
# Publish OFFLINE availability message
# function called by trap
publish_offline() {
	mosquitto_pub -q 1 -r -i $MOSQUITTO_CLIENT_ID -h $MOSQUITTO_HOST -p $MOSQUITTO_PORT -u $MOSQUITTO_USER -P $MOSQUITTO_PASS -t "${avail_topic}" -m "offline"
	# red
	tput setaf 1
   	printf "\rPublished ${SENSOR_NAME} offline\n"
	# reset format
    	tput sgr0
    	sleep 1
	# exit Python virtualenv
	deactivate
	exit 0
}

get_success_ratio() {
	# echo -e "\nSuccess rate = $(($aranetctl_count_success/$aranetctl_count_total))"

	#declare success_ratio=($aranetctl_count_success/$aranetctl_count_total)*100
	#success_ratio=$(bc <<< 'scale=3; ($aranetctl_count_success/$aranetctl_count_total)*100')
	success_ratio=$(echo "out= ${aranetctl_count_success}/${aranetctl_count_total}*100; scale=1; out/1" | bc -l)
	echo $success_ratio
}

# -----------------------------------------------------------------------------
# Python virtualenv created for aranetctl
source ${ARANETCTL_DIR}/activate

# When this script is forcibly terminated, publish offline message before exit
trap 'publish_offline' SIGINT SIGTERM

aranetctl_count_total=0
aranetctl_count_success=0

while [ true ]; do

	let aranetctl_count_total++
	echo ""
	date

	# wait 15s for aranetctl to return, otherwise kill process (rc=124)
	aranetctl_out=$(timeout 15s ${ARANETCTL_DIR}/aranetctl ${MAC})
	aranetctl_rc=$?

	if [[ $aranetctl_rc == 124 ]]; then 
		echo "aranetctl timeout, try again..."
		print_success_ratio
		sleep 5
	elif [[ $aranetctl_rc == 0 ]]; then
		let aranetctl_count_success++

		co2=$(echo "${aranetctl_out}" | awk 'FNR == 7 {print $2}' -)
		temp=$(echo "${aranetctl_out}" | awk 'FNR == 8 {print $2}' -)
		humidity=$(echo "${aranetctl_out}" | awk 'FNR == 9 {print $2}' -)
		pressure=$(echo "${aranetctl_out}" | awk 'FNR == 10 {print $2}' -)
		battery=$(echo "${aranetctl_out}" | awk 'FNR == 11 {print $2}' -)
		rate=$(get_success_ratio)

		#echo "${aranetctl_out}"
		echo "Publishing to MQTT..."
		echo "CO2         = ${co2} ppm"
		echo "temperature = ${temp} C"
		echo "humidity    = ${humidity} %"
		echo "pressure    = ${pressure} hPa"
		echo "battery     = ${battery} %"
		echo "success_rate= ${rate} %"
				
		# LWT will only trigger if mosquitto_pub is interrupted, not this shell script! For all other cases, trap will call publish_offline() before exit
		mosquitto_pub -i $MOSQUITTO_CLIENT_ID -h $MOSQUITTO_HOST -p $MOSQUITTO_PORT -u $MOSQUITTO_USER -P $MOSQUITTO_PASS --will-topic "${avail_topic}" --will-payload "offline" --will-retain --will-qos 1 -t "${state_topic}" -m "{\"temperature\":${temp}, \"humidity\":${humidity}, \"pressure\":${pressure}, \"carbon_dioxide\":${co2}, \"battery\":${battery}, \"success_rate\": ${rate}}"
		
		#printf '\nSuccess rate = %s %%\n' "${rate}"		
		sleep $REFRESH_RATE
	else
		# aranetctl returned before timeout, but returned an error
		# output likely stacktrace
		echo "${aranetctl_out}"
		echo "aranetctl returned ${aranetctl_rc}, try again..."
		get_success_ratio
		sleep 5
	fi
done
