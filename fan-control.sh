#!/bin/bash
# vim: set foldenable foldmethod=marker ts=4 sw=4:
# License Info                                                           {{{1
# Fan Control Script w/ Fan Curve
# Copyright (C) 2019 Barry Van Deerlin#
# Remastered by Stephanos B (16/05/2025)
# GNU General Public License v3.0+
# Note: I say "remastered" because I've tried to redo as much as possible, rather than just making small tweaks.
# Should keep support for multi-gpu setups but I don't have such a setup to test it
#

### Running the scrip {{{
    # 1. Use cron.
    # 2. Or run it manually by:
     # Use the logPath to "./logs" and run it with "sudo ./fan-control.sh -pc" in a terminal at the directory of the script
     # If you make a Application/Launcher then make sure the working directory is set where the script is located
### }}}

### ### ### Configurable Settings {{{

# FanControl Configuration Path
fanConfig="$(getent passwd $(id -un) | cut -d ':' -f6)/.fancontrol"

logsEnabled=true                    # When true will print out logs to files
#logPath="${HOME}/.fan-control/logs" # Change this to wherever you want the log files. This isen't required for function however
logPath="./logs"
tablePath="${logPath}/table.txt"    # This is inherited, just set the file name if you want to chage it 

defaultSpeed=60     # Default Fan Speed Setting
minSpeedG=30        # Min global fan speed % Set this to the lowest fan-min out of your GPUs or 0
declare -a minSpeed
minSpeed=( 30 )     # Min GPU-specific fan speed % MUST BE SET FOR EACH GPU. # Not sure if GPU-specific min's is really necessary

### Persistent Fan Curve Refresh Interval
refresh=2               # Max refresh time in seconds
adaptivRefresh=false    # When true, will adjust the refresh rate to adapt faster ounce temperature changes are detected. The greater the change that faster the script refreshes
minSleep=1              # Minimum delay for refreshing

### Fan Curve Settings
dCurveStart=12      # Day Curve Start Time (24 Hour Time)
nCurveStart=23      # Night Curve Start Time (24 Hour Time)
nCurveEnabled=false # Enable/Disable (true/false) switching to night curve when appropriate

MAXTHRESHOLD=60     # Fans will run at 100% if hotter than this temperature (°C)
minTempDrop=5       # Temperature (°C) must drop before updating
minTempTOT=6        # TimeOutTicks: Number of "Waits" before the minTempDrop is ignored. This is for when idle and the temp cannot drop enough to reach min fan-speed

temp_points[0]=0    dCurve[0]=$minSpeedG     nCurve[0]=$minSpeedG ### This point is fixed
### Set you custom fan curve here:
# GPU_temp (°C)     Day_Curve (%)   Night_Curve   (%)
temp_points[1]=30   dCurve[1]=30    nCurve[1]=30    #
temp_points[2]=45   dCurve[2]=60    nCurve[2]=45    #
temp_points[3]=60   dCurve[3]=100   nCurve[3]=100   # <- The final temperature entry should always have your set MAXTHRESHOLD value
## {{{
    # If there's a mismatch between the highest temp_point and MAXTHRESHOLD then here's what will happen:
    ## If the MAXTHRESHOLD is LOWER than your final temp_point then when your MAXTHRESHOLD is reached it will bypass the curve and default to 100% fan speed.
    #   But your fan-speeds prior to that are calculated with your last temp_pont so you will get a sudden jump in fan speed
    ## If your MAXTHRESHOLD is ABOVE your final temp_point: any temperature past your fan-curve will default to 100%
    #
    ## Bottom-line: I got you covered. If you want, treat your MAXTHRESHOLD as a emergency temerature, set it to like 75~80 and leave it. Then play with your fan-curve.

    # Alternative way to set the table
    #temp_points=( 0 30 45 "$MAXTHRESHOLD" )
    #dCurve=( "$minSpeedG" 30 60 100 )   # Day fan speeds (%)
    #nCurve=( "$minSpeedG" 30 45 100 )   # Night fan speeds
## }}}

### ### ### End Configurable Settings }}}
## Don't mess with stuff after this as a user ##

# Global vars {{{
export DISPLAY=':0' # Export Display (For Headless Use)
numGPUs=$(nvidia-smi --query-gpu=count --format=csv,noheader -i 0) # Get Number of connected GPUs

lastgputemp=()          # Previous temperatures (initialized on first run)
targetSpeed=$minSpeedG  # Track target per GPU
waitTOT=0               #
sleep_time=$minSleep    #
outputLog=0             # Logging verbosity
### }}}


### Functions {{{

# Function to enable manual fan control state on first run
initFCS()
{
    FanControlStates=($(nvidia-settings -q GPUFanControlState | grep 'Attribute' | awk -vFS=': ' -vRS='.' '{print $2}'))
    for i in ${FanControlStates[@]}; do
        if [ $i -eq 0 ]; then
            nvidia-settings -a "GPUFanControlState=1" > /dev/null 2>&1
            echo "Fan Control State Enabled"
            break
        fi
    done
} # initFCS()

# Function that applies Fan Curve
runCurve()
{
    # Get GPU Temperature and Current FanSpeed
    IFS=$'\n'
    gputemp=($(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader))
    currentSpeed=($(nvidia-smi --query-gpu=fan.speed --format=csv,noheader | awk '{print $1}'))
    unset IFS

    # Check the time and applies either the day or night curve respectively
    [ $nCurveEnabled ] && cTime=$(date +'%H') || cTime=$dCurveStart # Get the time by the current hour
    [ "$nCurveEnabled" = true ] && ( ((cTime < dCurveStart || cTime >= nCurveStart)) && speed_points=("${nCurve[@]}") ) || speed_points=("${dCurve[@]}")

    # Loop through each GPU
    for i in $(seq 0 $((numGPUs-1))); do
        speed=100 # If temperatrue is outside fan-curve it will be set to this
        
        local gpu_temp=${gputemp[i]}
        local curr_speed=${currentSpeed[i]}
        local tempDelta=$(( lastgputemp[${i}] - gpu_temp )) # Delta being the change in temperature
        [ $outputLog == 2 ] && echo "→ → Δ$tempDelta°C >= $minTempDrop°C OR $gpu_temp°C >= ${lastgputemp[i]}°C" # Debug #

        # Only updates if the temperature decreases by a minimum amount OR increases OR waiting times out
        if [[ $tempDelta -ge $minTempDrop || $gpu_temp -ge ${lastgputemp[${i}]} || $waitTOT -ge $minTempTOT ]]; then 
            waitTOT=0 # resets the TOT for minTempDrop
                
            if [ ${gputemp[$i]} -lt $MAXTHRESHOLD ]; then
                # Applies the fan curve. Note k=1 to skip the 0 temp entry. This is needed to solving the gradient
                for ((k=1; k<${#temp_points[@]}; k++)); do
                    [ "${gputemp[i]}" -le "${temp_points[k]}" ] && {
                        speed=$(( speed_points[k] + (speed_points[k]-speed_points[k-1]) / (temp_points[k]-temp_points[k-1])*(gputemp[i] - temp_points[k]) ))
                        break
                    }
                done # for k
            fi

                [ "$speed" -lt "${minSpeed[$i]}" ] && speed="${minSpeed[$i]}" # If target fan speed is below that specific GPUs min then set it to the correct min to avoid errors

                if [ "$speed" -ne "$curr_speed" ]; then
                    # If the this point is reached and the previously set speed is the same as the new desired speed, that means the fans are still catching up
                        # This avoids spamming the fans to the same target speed while still updating the target if it changes
                    [ $outputLog == 2 ] && echo "→ → CurrentSpeed: $curr_speed% | TargetSpeed: $targetSpeed% | Speed to apply: $speed%" # Debug #
                    if [ "$speed" == "$targetSpeed" ]; then
                        [ $outputLog -ge 1 ] && echo "→ Target fan-speed not reached yet"
                        break
                    fi

                    [ $outputLog -ge 1 ] && echo "→ Temp $gpu_temp°C -> Speed: $speed%" # Debug # Changed this to set all fans, not ID each fan
                    [ $logsEnabled == true ] && printf "%-20s |%4s |%4s°C |%6s%%| %6s%%\n" $(date +"%Y-%m-%d_%H-%M-%S") $i $gpu_temp $speed $curr_speed >> "$tablePath" # Logs all fan changes in the log-file

                    targetSpeed=$speed
                    nvidia-settings -a "GPUTargetFanSpeed=$speed"
                    else
                        [ $outputLog -ge 1 ] && echo "→ No change" # Debug # Changed this to set all fans, not ID each fan
                fi
                lastgputemp[$i]=$gpu_temp # Grabs the previous values for current GPU temperature
            else
                waitTOT=$((waitTOT + 1))
                [ $outputLog -ge 1 ] && echo "→ Waiting for drop.  [TimeOutTicks: $waitTOT / $minTempTOT]"
        fi
    done # for i

    ### End of curve activity ###
    [[ $outputLog -ge 1 ]] && echo "" # Debug #

    # Adaptive sleep calculation
    [[ $adaptivRefresh == true ]] && {
        local delta_abs=${tempDelta#-}  # Absolute value of delta
        local m=$(( refresh - minSleep )) 
        sleep_time=$(( refresh - (delta_abs * (refresh-minSleep)) / MAXTHRESHOLD ))
        (( sleep_time < minSleep )) && sleep_time=$minSleep
    } || sleep_time=$refresh

    sleep "$sleep_time"
} # runCurve()

# Function that gets GPU Fan Stats and displays them
getInfo()
{
    IFS=$'\n'
    query=($(nvidia-smi --query-gpu=name,fan.speed,temperature.gpu --format=csv,noheader)) # Retrieve GPU Names,  Fan Speed, and Temperature
    query_rpm=($(nvidia-settings -q GPUCurrentFanSpeedRPM | grep "fan:" | awk -F ': ' -vRS='.' '{print $2}')) # Retrieve GPU Fan RPM

    # Summary format:
    # | id: Card                           |  Fan%|     RPM| Temp°C|
    # |  0: NVIDIA GeForce RTX 30600       |   30%|    1301|   27°C|
    
    
    printf "Nvidia Fan Info:\n|%3s: %-30s|%5s%%|%8s|%5s°C|\n" "id" "Card" "Fan" "RPM" "Temp" # Print out Header

    # Loop through GPUs to compile summary
    for i in $(seq 0 $((numGPUs-1))); do
        card=$(awk -F ', ' '{print $1}' <<< ${query[$i]})
        fan_speed=$(awk -F ', ' '{print $2}' <<< ${query[$i]} | awk '{print $1}')
        fan_rpm=${query_rpm[$i]}
        temp=$(awk -F ', ' '{print $3}' <<< ${query[$i]})
        printf "|%3s: %-30s|%5s%%|%8s|%5s°C|\n" $i $card $fan_speed $fan_rpm $temp
    done

    unset IFS
} # getInfo()

# Writes current configuration settings to a file
printConfig()
{
    tee <<EOF
### Debug details: ###

fan_config path = $fanConfig
logsEnabled = $logsEnabled
log path = $logPath
tablePath = $tablePath

GPUs detected = $numGPUs


### User deployment setting: ###

defaultSpeed = $defaultSpeed
minSpeedG = $minSpeedG
minSpeed = ${minSpeed[@]}

refresh = $refresh
adaptivRefresh = $adaptivRefresh
minSleep = $minSleep

dCurveStart = $dCurveStart
nCurveStart = $nCurveStart
nCurveEnabled = $nCurveEnabled

MAXTHRESHOLD = $MAXTHRESHOLD
minTempDrop = $minTempDrop
minTempTOT = $minTempTOT

EOF

    printf "\n### Fan Curve ###\n  |%5s°C |%5s%% |%5s%% |\n" "Temp" "Day" "Night"
    for ((i=0; i<${#temp_points[@]}; i++)); do
        printf "  |%5s°C |%5s%% |%5s%% |\n" ${temp_points[i]} ${dCurve[i]} ${nCurve[i]}
    done # for i

    echo -e "\nLogged at: $logPath/config.log\n\n"

} # printConfig()

### /Functions }}}


### Main Execution {{{
# Parse and Execute Arguments passed to script
case "$1" in
    # Set Fan Speed for all GPU Fans
    -s|--set)
        case "$2" in
            # Enable Fan Curve (Use with Cron)
            curve|c)        speed="curve" ;;

            # Set Speed to Default
            default|d)      speed=$defaultSpeed ;;

            # Set Speed to Max
            max|m|100)      speed=100 ;;

            # Turn Fans Off
            off)            speed=0 ;;

            # Set Fan Speed Manually
            [0-9]|[1-9][0-9])   speed=$2 ;;

            # Improper Input Given
            *)          echo "Usage: $0 $1 {# Between 0 - 100|d (default)|m (max)|off|curve}"; exit 2 ;;
        esac

        # 
        if [ "$speed" -lt $minSpeedG ]; then
            echo "Entered speed ($speed%) is below your minimum fan-speed ($minSpeedG%)"
            exit 2
        fi

        case "$speed" in
            curve)
                echo curve > $fanConfig # Change Configuration to Curve
                $0 curve # Run Fan Curve
                ;;
            *)
                echo manual > $fanConfig # Enabling Manual Control and Disabling Fan Curve
                initFCS
                #nvidia-settings -a "GPUTargetFanSpeed=$speed"

                # If the entered speed is too low for that specific GPU then it will use the GPU's min to avoid errors.
                # This ensure each GPU is set to the lowest value they can reach to try reach the target
                for i in $(seq 0 $((numGPUs-1))); do
                
                    if [ "$speed" -lt "${minSpeed[$i]}%" ]; then
                        echo "→ Entered speed ($speed%) is below your minimum fan-speed for GPU[$i] (${minSpeed[$i]}%)"
                        speed=${minSpeed[$i]}
                    fi
                    nvidia-settings -a "GPUTargetFanSpeed=$speed"
                done # for i
                ;;
        esac
        ;;

    # For testing Individual GPU Fan Settings
    -dx)
        # Test if Proper Input was given
        # Is input $2 a valid GPU index? Is input $3 a number that is less than or equal to 100?
        re='^[0-9]{,2}$'
        [ $# -eq 3 ] && [[ $2 =~ $re && $2 -lt $numGPUs ]] && [[ $3 =~ $re || $3 -eq 100 ]] \
        && nvidia-settings \
            -a "[gpu:$2]/GPUFanControlState=1" \
            -a "[fan:$2]/GPUTargetFanSpeed=$3"

        [ $? -ne 0 ] && { echo "Usage: $0 $1  gpuIndex  FanSpeed Between 0 - 100"; exit 2; }
        ;;

    # Applies Fan Curve (For use with cron)
    -c|--curve)
        # Checks if Configuration File exists and create it if it doesn't
        [ ! -f $fanConfig ] && echo "curve" > $fanConfig

        # Run fan curve if configuration is set to curve
        case "$(cat $fanConfig)" in
            curve)
                initFCS
                runCurve
                ;;
        esac
        ;;

    # Applies Persistant Fan Curve (For use without cron)
    -pc|--pcurve)
        echo "pcurve" > $fanConfig
        initFCS

        # Initiates the log file with a header.
            # The intent of this log is to show all fan-speed changes made with a temperature and timestamp
            # With this you could make a graph for more indepth debugging
        [[ $logsEnabled == true && ! -d $logPath ]] && mkdir -p "$logPath"
        [ $logsEnabled == true ] && printf "%-20s |%4s |%4s°C |%6s%%| %6s%%\n" "time" "gpu" "temp" "Target" "Actual" > "$tablePath"

        # Lets 
        case "$2" in
            # Sets log outputs to basic
            -o|--out)
                outputLog=1
            ;;

            # Sets log outputs to advanced/debug
            -de|--debug)
                outputLog=2
            ;;

            # Shows a usage tip and stops
            -h|--help)
                #echo "Usage: $0 $1 {out|o for output-logs}"
                echo -e "usage: ./fan-control.sh $0 $1 {options}\options:"
                printf "  |%4s, %-10s| %s\n" "-o" "out" "prints out basic logs to the console (recommended when testing your fan-curve)"
                printf "  |%4s, %-10s| %s\n" "-de" "debug" "Prints out advanced/debugging logs to the console"
                printf "  |%4s, %-10s| %s\n" "-h" "help" "Display full help and usage for operation"
                exit 1
            ;;

            # if not requested, log outputs are minimal
            *)          outputLog=0 ;;
        esac

        [ $logsEnabled == true ] && printConfig > "$logPath/config.log"

        # Run while configuration is set to pcurve
        while [ "$(cat $fanConfig)" == "pcurve" ]; do
            [ $logsEnabled == true ] && runCurve | tee -a "$logPath/debug.log" || runCurve
        done
        ;;

    # Display GPU Fan and Temp Status
    -i|--info)
        getInfo
        ;;

    # Prints out the current deplyment settings
    -con|--config)
        printConfig | tee "$logPath/config.log"
        ;;

    # Display Version Info
    -v|--version)
        echo "$0 v0.2 Remastered by Stephanos B from [Copyright (C) 2019 Barry Van Deerlin]"
        ;;

    # Display a full help and usage section
    -h|--help)
        echo -e "usage: ./fan-control.sh <operation> [...]\noperations:"
        printf "  |%4s, %-10s| %s\n" "-s" "--set" "Set all fans for all GPUs to a speed"  # Could be complressed into a single printf but that got a bit messy
        printf "  |%4s, %-10s| %s\n" "-dx" "" "For testing Individual GPU Fan Settings"
        printf "  |%4s, %-10s| %s\n" "-c" "--curve" "Applies Fan Curve (For use with cron)"
        printf "  |%4s, %-10s| %s\n" "-pc" "--pcurve" "Applies Persistent Fan Curve (For use without cron)"
        printf "  |%4s, %-10s| %s\n" "-i" "--info" "Display GPU, Fan and Temp Status for each GPU in a table"
        printf "  |%4s, %-10s| %s\n" "-con" "--config" "Prints out the current deplyment settings to console and a config.log file"
        printf "  |%4s, %-10s| %s\n" "-V" "--version" "Display version/credits info for this script"
        printf "  |%4s, %-10s| %s\n" "-h" "--help" "Display full help and usage"
        ;;

    # Incorrect Usage
    *)
        echo "no operation specified (use -h or --help for usage help)"
        exit 2
esac

### Main Execution }}}

exit $?
