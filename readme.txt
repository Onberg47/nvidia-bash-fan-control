
### Running the scrip {{{
    # 1. Use cron.
    # 2. Or run it manually by:
        # For this example the scrip is in a directory ".fan-control" in my user-home. (Update logPath is you want to do it differently)
         # A: Use the logPath to "./logs" and run it with "sudo ./fan-control.sh -pc" in a terminal at the directory of the script (If you make a Application/Launcher then make sure the working directory is set where the script is located)
         # B: Use: "sudo -u {YourUserName} $HOME/.fan-control/fan-control.sh -pc" # This is to ensure the user's Home directly is found and created files belong to the user not root
         # C: Don't care about logs and just run the script wherever with sudo. The script only need paths for the logs
### }}}