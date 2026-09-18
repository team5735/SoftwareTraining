# SoftwareTrainingDocs

## Steps for installing WPILib:

### Optional but recommended steps:
Open a new tab, type `about:flags`, and press enter.

Search for "crostini" and select "Enabled" in the dropdown box for "Crostini GPU Support".

Restart your Chromebook with the button at the bottom of the window.

Now continue with the required steps.

### Required steps:
Go to Settings -> About ChromeOS -> Linux development environment -> click "Set Up". Click "Next".

Change your username if you'd like, but leaving it alone is fine.

Click "Custom" and drag the slider to at least 20 GB. Click "Install".

Wait for the installation process to finish.

Once it's done, go to the terminal window that was opened, paste in this command, and hit enter:

```sh
bash <(curl https://raw.githubusercontent.com/team5735/SoftwareTraining/refs/heads/main/setup.sh) 2027.0.0-alpha-7
```

If a different version of WPILib is needed, such as 2026.2.1, re-enter the above command, but replace 2027.0.0-alpha-7 with the version you want. If you need to uninstall a WPILib version, replace the version with --kill and follow the directions.
