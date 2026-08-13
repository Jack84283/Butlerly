# Physical iPhone deployment

Before running the script:

1. Connect and trust the iPhone, then enable Developer Mode on it.
2. Open `../../../ios/Runner.xcodeproj` in Xcode.
3. Select **Runner > Signing & Capabilities**.
4. Enable automatic signing and select your Apple Developer team.
5. Run `./deploy.sh <device-id>`.

Run `flutter devices` to find the device ID. The script builds, signs, installs,
and launches the current source rather than using the unsigned packaged archive.
