# ZChess

A real-time chess application built with Flutter, connecting to the Lichess API for online gameplay. 

## Features ✨


## Getting Started 🚀

Follow these instructions to get a copy of the project up and running on your local machine for development and testing purposes.

### Prerequisites

Before you begin, ensure you have the following installed:

1.  **Flutter SDK**
    * Go to: [https://docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install)
    * Choose your operating system (Windows, macOS, Linux, ChromeOS) and follow the detailed installation instructions.
    * **Verify Installation:** Open your terminal or command prompt and run:
        ```bash
        flutter doctor
        ```
        This command checks your environment and displays a report of the status of your Flutter installation. Address any issues reported.

2.  **Android Studio / VS Code + Required Plugins**
    * **Install an IDE:** Choose either [Android Studio](https://developer.android.com/studio) or [Visual Studio Code](https://code.visualstudio.com/).
    * **Install Plugins:** Make sure the **Flutter** and **Dart** plugins are installed in your chosen editor. These provide syntax highlighting, code completion, debugging tools, and more.
    * **Set up a Device:**
        * **Android Emulator:** Set up an Android Virtual Device (AVD) using Android Studio's AVD Manager.
        * **Physical Device:** Connect a physical Android mobile device via a USB cable. Ensure **USB debugging** is turned on in your device's Developer Options.

### Installation

1.  **Clone the repository:**
    Open your terminal or command prompt and run:
    ```bash
    git clone [https://github.com/mhdaslamp/ZChess.git](https://github.com/mhdaslamp/ZChess.git)
    ```

2.  **Navigate to the project directory:**
    ```bash
    cd ZChess
    ```

3.  **Install Project Dependencies:**
    Fetch all the necessary Dart packages for the project:
    ```bash
    flutter pub get
    ```
    * **Note on `pubspec.yaml` errors:** If you encounter issues related to `pubspec.yaml` dependencies, it might be due to Flutter version compatibility. This repository is developed and tested with **Flutter 3.22.1**. You can switch your Flutter version using `fvm` (Flutter Version Management) or by directly installing that specific version.

### Running the App

1.  **Connect a Device:**
    Ensure an Android emulator is running or a physical device is connected and recognized by Flutter. You can check connected devices by running:
    ```bash
    flutter devices
    ```

2.  **Run the application:**
    With your device connected and the project dependencies installed, run the app:
    ```bash
    flutter run
    ```

The app should now launch on your connected device or emulator. 
