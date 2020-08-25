#! /bin/sh
###############################################################################
# Fetch Purple Air sensor readings, average, and email if too high
#
# aqi-alert@smitasin.com 2020-08-24
#
###############################################################################
### LOCAL VARIABLES

# Contact
MAILTO="<EMAIL ADDRESS>"

# Paths
READINGSFILE="/var/tmp/aqi-readings"
STATEFILE="/var/tmp/aqi-state"

# Initial values
SENSORS="<SENSORLIST>"

###############################################################################
### FUNCTIONS

FETCHREADING(){
	touch $READINGSFILE
	rm $READINGSFILE
	for SENSORID in $SENSORS
	do
		curl -s "https://www.purpleair.com/json?show=$SENSORID" | jq -r .results[].PM2_5Value | fgrep -v "0.0" >> $READINGSFILE
		sleep 5
	done
}

CONVERTAQI(){
	if [ "$READINGAVERAGE" -ge 0 -a "$READINGAVERAGE" -le 12 ]
	then
		AQI=$(echo "(( 50 - 0 ) / ( 12 - 0 )) * ( $READINGAVERAGE - 0 ) + 0" | bc)
	elif [ "$READINGAVERAGE" -ge 13 -a "$READINGAVERAGE" -le 35 ]
	then
		AQI=$(echo "(( 100 - 51 ) / ( 35 - 13 )) * ( $READINGAVERAGE - 13 ) + 51" | bc)
	elif [ "$READINGAVERAGE" -ge 36 -a "$READINGAVERAGE" -le 55 ]
	then
		AQI=$(echo "(( 150 - 101 ) / ( 55 - 36 )) * ( $READINGAVERAGE - 36 ) + 101" | bc)
	elif [ "$READINGAVERAGE" -ge 56 -a "$READINGAVERAGE" -le 150 ]
	then
		AQI=$(echo "(( 200 - 151 ) / ( 150 - 56 )) * ( $READINGAVERAGE - 56 ) + 151" | bc)
	elif [ "$READINGAVERAGE" -ge 151 -a "$READINGAVERAGE" -le 250 ]
	then
		AQI=$(echo "(( 300 - 201 ) / ( 250 - 151 )) * ( $READINGAVERAGE - 151 ) + 201" | bc)
	elif [ "$READINGAVERAGE" -ge 251 -a "$READINGAVERAGE" -le 350 ]
	then
		AQI=$(echo "(( 400 - 301 ) / ( 350 - 251 )) * ( $READINGAVERAGE - 251 ) + 301" | bc)
	elif [ "$READINGAVERAGE" -ge 351 -a "$READINGAVERAGE" -le 500 ]
	then
		AQI=$(echo "(( 500 - 401 ) / ( 500 - 351 )) * ( $READINGAVERAGE - 351 ) + 401" | bc)
	else
		echo "$READINGAVERAGE = OUT OF RANGE"
		exit 1
	fi
}

CHECKSTATE(){
	CURRSTATE=$(cat $STATEFILE)
	if [ "$CURRSTATE" -eq 1 ]
	then
		# Alert already in effect
		continue
	elif [ "$CURRSTATE" -eq 0 ]
	then
		# Send alert
		BUILDALERT | /usr/sbin/sendmail -t
		echo "1" > $STATEFILE
	fi
}

BUILDWARN(){
	echo "From: $MAILTO"
	echo "To: $MAILTO"
	echo "Subject: AQI Warning - Current: $AQI, Last $LASTAQI, Diff $DIFF"
	echo "Generated from $(hostname):$0"
}

BUILDALERT(){
	echo "From: $MAILTO"
	echo "To: $MAILTO"
	echo "Subject: AQI Alert - Current: $AQI"
	echo "Generated from $(hostname):$0"
}

MONITOR(){
	LASTAQI="$AQI"
	# wait 10 mins before fetching again and comparing
	sleep 600
	FETCHREADING
	CONVERTAQI
	DIFF=$(echo "$AQI - $LASTAQI" | bc)
	# alert if increase is greater than 10 in 10 mins
	if [ "$DIFF" -gt "10" ]
	then
		BUILDWARN | /usr/sbin/sendmail -t
	fi
	
}	

###############################################################################
### EXECUTION

FETCHREADING
READINGAVERAGE=$(cat $READINGSFILE | awk '{sum+=$1} END {print sum/NR}' | cut -d"." -f1)
CONVERTAQI

if [ "$AQI" -le "75" ]
then
	# Clear state
	echo "0" > $STATEFILE
elif [ "$AQI" -gt "75" -a "$AQI" -lt "95"]
then
	MONITOR
elif [ "$AQI" -ge "95" ]
then
	CHECKSTATE
fi

###############################################################################
### CLEANUP, log, exit cleanly
exit 0
