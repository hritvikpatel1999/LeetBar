# LeetBar

## LeetBar Overview

LeetBar puts your LeetCode daily challenge, streak, contest rating, practice totals, and upcoming contests in the macOS menu bar. Keep up to four personal practice links one click away in its expandable Quick Links section.

LeetBar is an unofficial companion, not affiliated with LeetCode. The LeetCode name and logo belong to LeetCode.

## Download This If You

- Want a quick check of your daily challenge completion and streak.
- Track today's submissions and distinct problems solved.
- Want your contest rating and upcoming contest times at a glance.
- Keep practice sheets, notes, or study plans online and want shortcuts to them.

**Currently available as source code only.** There is no packaged DMG release yet; build and run the app using either method below.

## System Requirements

- **macOS 14 or later.** Currently tested on Apple Silicon; Intel compatibility has not been verified.
- **Xcode with Swift 6 support** to build from source. Tested with Xcode 26.5. Install full Xcode, not just the standalone Command Line Tools.
- **Internet access and a LeetCode account** for live statistics. Quick Links work without a connected account.
- **Chrome** for the account-connection instructions below. Other browsers have different developer-tool menus.
- **XcodeGen 2.45 or later**, only if regenerating the project. It is not required to open or build the included Xcode project.

No paid Apple developer account is needed to build and run locally. These local builds are not notarized distribution builds.

## Connect Your Account

After launching LeetBar:

1. Click its menu-bar icon, open the gear, and select **Open LeetCode Sign-In**.
2. Sign in on LeetCode in your browser. Choose **Google** if that is how you access your LeetCode account.
3. Stay on a signed-in leetcode.com page. In Chrome, press **Option-Command-I**, open **Application**, then **Storage > Cookies > https://leetcode.com**.
4. Copy only the **Value** of **LEETCODE_SESSION** into its matching masked field in LeetBar Settings.
5. Copy the **csrftoken** value from the same browser session into the other field. Do not copy an entire Cookie header.
6. Click **Connect**. Your username and live data appear after verification.
7. Clear your clipboard after pasting.

**Treat session cookies like passwords. Never share them in chat, screenshots, logs, or GitHub issues.** Enter them only into LeetBar's masked fields. LeetBar stores the session in your local macOS Keychain; it does not request your Google password or Gmail access.

The saved session is reused across launches. If it expires, repeat the steps with fresh values and choose **Reconnect**. **Disconnect** removes LeetBar's saved session but does not sign your browser out. macOS may request Keychain approval after a local rebuild; enter any requested Mac password only in the system dialog.

This is a manual browser-session connection, not automatic Google OAuth. LeetBar uses unofficial website endpoints that may change; review [LeetCode's terms](https://leetcode.com/terms/) before use.

## Run It in Xcode

1. Clone or download this repository and open [LeetBar.xcodeproj](LeetBar.xcodeproj).
2. Select the **LeetBar** scheme and **My Mac** destination in the toolbar.
3. Quit any already-running copy of LeetBar using the power button in its dropdown.
4. Press **Command-R** to build and run.
5. Look for the LeetCode logo in your **menu bar**. LeetBar intentionally has no Dock icon or main window.
6. Open Settings to connect your account and configure up to four **Quick Links**.

Press **Command-U** to run the tests, or **Command-Period** to stop an Xcode-launched app.

## Build From Your Terminal

From the repository root, build and launch:

```sh
xcodebuild -project LeetBar.xcodeproj -scheme LeetBar -configuration Debug -destination 'platform=macOS' -derivedDataPath .build build
open .build/Build/Products/Debug/LeetBar.app
```

Quit an existing copy before launching a rebuilt app. Run the tests with:

```sh
xcodebuild -project LeetBar.xcodeproj -scheme LeetBar -destination 'platform=macOS' -derivedDataPath .build test
```

The included Xcode project is ready to build. If you change [project.yml](project.yml) or add/remove source files outside Xcode, regenerate it using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

If needed, install XcodeGen with Homebrew:

```sh
brew install xcodegen
```