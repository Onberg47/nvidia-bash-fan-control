# nvidia-bash-fan-control
Fan Curve Control Script for Nvidia GPUs on Linux desinged to offer some nifty features and debugging data.

# What this is about
A simple way to apply a fan-curve to Nvidia cards on Linux through a termial.

# Features and support
- A fan-speed to temperature curve with no limits on the number of points.
- Multi-GPU support
- The curve is global, all GPUs are set to follow it.
- Prints out log, config and modification data to a file.

## How to implement/run

  # As an Application:
  - Put the script in a directory on your user-home (eg: .fan-control) and set the log paths to "./logs". This will set the logs to be in the current directory when the script runs.
  - Crate a new Application that runs in a terminal, the working directory is where you have the script located.
  - The running command: `sudo ./fan-control.sh -pc` plus any options you want.
  
    This will keep everything inside your working directory without the script needing to be adjusted.
    Its pretty simple and rudementary but its how I like to run it.

  # With cron:
  This can and is probably better run with cron, especially if you want it to auto-start and run without a terminal.
  I'm not familiar with cron, you'll need to lookup on the usage for cron.
    
