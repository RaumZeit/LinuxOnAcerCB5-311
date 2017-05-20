#!/bin/sh
#
# Script to change brightness  for laptops which don't respond to hardware keys
# Needs to have write permissions to /sys/class/backlight/pwm-backlight/brightness
# which can be set in /etc/rc.local
#

BRIGHT_INCREMENT=2
MIN_BRIGHT=1

read MAX_BRIGHT < /sys/class/backlight/pwm-backlight/max_brightness
read CURRENT_BRIGHT < /sys/class/backlight/pwm-backlight/brightness

case $1 in
"up")
        CURRENT_BRIGHT=`expr $CURRENT_BRIGHT + $BRIGHT_INCREMENT`
        ;;
"down")
        CURRENT_BRIGHT=`expr $CURRENT_BRIGHT - $BRIGHT_INCREMENT`
        ;;
*)
        ;;
esac

if [ $CURRENT_BRIGHT -ge $MIN_BRIGHT ] && [ $CURRENT_BRIGHT -le $MAX_BRIGHT ]
then
        echo $CURRENT_BRIGHT > /sys/class/backlight/pwm-backlight/brightness
fi
