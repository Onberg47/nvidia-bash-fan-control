### nvidia-bash-fan-control
Fan Curve Control Script for Nvidia GPUs on Linux designed to offer some nifty features and debugging data.

# What this is about
A simple way to apply a fan-curve to Nvidia cards on Linux through a terminal.

# Features and support rough overview
- A fan-speed to temperature curve with no limits on the number of points.
- Recognises when fan-speeds are lagging behind the target to avoid spamming the fans to reach a target speed they already are changing to.
- Multi-GPU support
- The curve is global, all GPUs are set to follow it.

- Prints out log, config and modification data to a file.
  - The log file contains all console outputs that took place in the current/last instance of the script
  - The config *log* file just logs out all the user-settings and detected data to a file when the script runs.
  - The modification-data or "table.log" is a file that records only the changes to the fan-speed.
    It records each entry in a tabular format with a timestamp; GPU ID; GPU Temperature; Set fan-speed% and the Actual (hardware value) fan-speed%
  - Logging these files can be disabled in the script settings.

- Minimum temperature drops before slowing fan-speeds to ensure good and consistent cooling.


---

### Configuration and Operations

# Configuration setting

  #Path Settings
`logsEnabled` - When true will print out logs to files.
  
`logPath` - This is the directory where all the log files will be created
  
`tablePath` - This is inherited from the log-path, just set the file name if you want to chage it.

  #Fan-Speed Settings
`defaultSpeed` - Default Fan Speed Setting.

`minSpeedG` - Min global fan speed % Set this to the lowest fan-min out of your GPUs or 0

`minSpeed` - Min GPU-specific fan speed % MUST BE SET FOR EACH GPU. This is in case you have two GPUs and one can have a lower fan-speed% than the other. Instead of narrowing your fan-speed curve to your highest min.
             This means that if the fan-curve goes below what one of your GPUs can be set to, *only* that GPU will be set to its minimum to get as close as it can, while the other GPU(s) that can go lower will match the curve if they can.
             The goal is to ensure that a GPU is never set to a speed it cannot reach, which would cause it to not update at all. This way every GPU will follow the curve to the best of its abilities.

  #Persistent Fan Curve Refresh Interval
`refresh` - Max or constant refresh time in seconds.

`adaptivRefresh` - When true, will adjust the refresh rate to adapt faster ounce temperature changes are detected.
                   The greater the change that faster the script refreshes to keep-up with dynamic situations to try optimise the refresh rate.
                   This works by refreshing at rates between `refresh` and `minSleep`, reducing the sleep time (increasing the refresh rate) in proportion to the the temperature changes. When the GPU is idle, refreshes slowly. When the temperature changes it refreshes quickly to make fan-changes more rapidly.
                   If you use this, `refresh` should be over 5 seconds otherwise its a waste. Ideally 10-15 seconds or higher.
`minSleep` - Minimum delay for refreshing, only applicable when dynamic `adaptivRefresh` is enabled. This can be 0.

  #Fan Curve Settings
`dCurveStart` - Day Curve Start Time (24 Hour Time)

`nCurveStart` - Night Curve Start Time (24 Hour Time)

`nCurveEnabled` - Enable/Disable (true/false) switching to night curve when appropriate.

`MAXTHRESHOLD` - Fans will run at 100% if hotter than this temperature (°C), bypassing the curve.

`minTempDrop` - Temperature (°C) must drop before updating. This is to reduce the rate at which the fans slow-down with the curve, forcing them to stay high when the temperature only drops small amounts.

`minTempTOT` - TimeOutTicks: Number of "Waits" before the minTempDrop requirement is ignored. This is for when idle and the temp cannot drop enough to reach min fan-speed.


---

# Operations of interest

  Set:
    This will manually set every fan on every GPU to your specified speed unless:
      - Your input speed is below your global min-speed, then it will return an error/warning
      - If your input speed is below what a GPU can reach, then it will default to the min for that GPU
    I think this operation is not required, using Nvidia-SMI is rather straight forward and is exactly how it is applied. I may remove or simply this to reduce bulk in the script.
  
  Info:
    This will output basic information about your connected GPUs
```
Nvidia Fan Info:
| id: Card                          |  Fan%|     RPM| Temp°C|
|  0: NVIDIA GeForce RTX 3060       |   30%|    1301|   27°C|

```

  Config:
    This will print to the console and write to the `config.log` file the current script settings, this includes the user-set settings *and* the auto-detected settings.
    The aim is to have a clear view of what data the script is using, to validate your settings are correctly interrupted.
    This is mostly a debugging tool, not of much use to normal users, I think.


---

### Usage output
As expected, `-h` and `--help` operations will provide usage help for the script and using it with an operation that has options will provide detailed help for that operation, example: `./fan-control.sh -pc -h` will provide the full help for the Persistent Curve operation.

Here is a sample of the general help:
```
[USER .fan-control]$ ./fan-control.sh --help
usage: ./fan-control.sh <operation> [...]
operations:
  |  -s, --set     | Set all fans for all GPUs to a speed
  | -dx,           | For testing Individual GPU Fan Settings
  |  -c, --curve   | Applies Fan Curve (For use with cron)
  | -pc, --pcurve  | Applies Persistent Fan Curve (For use without cron)
  |  -i, --info    | Display GPU, Fan and Temp Status for each GPU in a table
  |-con, --config  | Prints out the current deplyment settings to console and a config.log file
  |  -V, --version | Display version/credits info for this script
  |  -h, --help    | Display full help and usage
```


---

### How to implement/run

  # As an Application:
  - Put the script in a directory on your user-home (eg: .fan-control) and set the log paths to "./logs". This will set the logs to be in the current directory when the script runs.
  - Crate a new Application that runs in a terminal, the working directory is where you have the script located.
  - The running command: `sudo ./fan-control.sh -pc` plus any options you want.
  
    This will keep everything inside your working directory without the script needing to be adjusted.
    Its pretty simple and rudementary but its how I like to run it.

  # With cron:
  This can and is probably better run with cron, especially if you want it to auto-start and run without a terminal.
  I'm not familiar with cron, you'll need to lookup on the usage for cron.
    
