# Headless Flutter Renderer

This is a headless Flutter renderer that can be used to render Flutter widgets to images. Using C lib with flutter embedded to create the binary.

## Debugging

To debug, you can use flutter normally, the unique difference, is that since this is headless, it will not have an UI, so you need to run the app as a flutter test, since tests does not launch any device!

```sh
fvm flutter run -d flutter-tester lib/main.dart
```

If you want to run in a IDE to debug the code, VS Code is already configured, but if you want to configure it yourself, the strategy is:

Since we should not launch any device, and Dart extension insist to launch a device if I try to run any file outside of test folder, I've made a trick to workaround that. We have the `test/debug_main_test.dart` file, that is a simple test file that calls the `main` function from `lib/main.dart`. Resulting in the same thing as running directly from the main file, but without launching any device.

## Requirements

- fvm (flutter version manager)
- git
- python3
- [depot_tools](https://commondatastorage.googleapis.com/chrome-infra-docs/flat/depot_tools/docs/html/depot_tools_tutorial.html#_setting_up)
  - You need to clone the repo and add it to the PATH
  - After cloning, go to depot_tools folder and run:
  - `git config --global depot-tools.allowGlobalGitConfig true`
  - `git cl creds-check --global`
  <!-- - `mkdir chromium`
  - `cd chromium`
  - `fetch --no-history chromium` -->
- On Windows:
  - Visual Studio 2017 or later
  - Windows SDK (usually already installed if you have Visual Studio installed)
    - I would recommend do not install yet, because each flutter version, uses a different version of the SDK so let's wait for the exception to happen to know which version to install

## Prepare the environment

Open a terminal on the root of the project
Run `fvm use` to install and use the correct flutter version
Run `fvm flutter doctor` to ensure the environment is setup correctly
Run `fvm flutter pub get` to install the dependencies

## Build Flutter Engine (run that every time you update flutter version)

For more details, please refer to the [flutter engine docs](https://github.com/flutter/flutter/blob/master/docs/engine/contributing/Setting-up-the-Engine-development-environment.md).

Open a terminal on the root of the project, then run:

```sh
cd .fvm/flutter_sdk/
cp ./engine/scripts/standard.gclient .gclient
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0" # If you are on windows
gclient sync
```

Depending on your python version, you can get that error "ModuleNotFoundError: No module named 'pipes'"
To fix that you can go to `.fvm\flutter_sdk\engine\src\build\vs_toolchain.py` and remove the line `import pipes`

Now that we have the repository synced, we can build the flutter engine.
For that we will use `et` tool, provided by flutter engine.

Continue using the same terminal, then run:

```sh
cd engine/src
./flutter/bin/et build --config host_release
```

Probably you will get an error saying that the computer is missing Windows SDK. "Exception: Path "C:\Program Files (x86)\Windows Kits\10\\include\10.0.22621.0\\um" from environment variable "include" does not exist. Make sure the necessary SDK is installed."

To fix that, look at your error message and search for the version, it is at the end of the path, in this case it is `10.0.22621.0`
Now go to [Windows SDK](https://developer.microsoft.com/en-us/windows/downloads/windows-10-sdk) and download the SDK for your version.
After downloading, install it and then run the command again.

```sh
./flutter/bin/et build --config host_release
```

That will produce a folder called `out/host_release` with the flutter engine binaries.

Let's copy the engine binaries to the project, at `clib/lib/{os-arch}/` folder, so we can use them later.

Depending on your operating system you will have different binaries you need to copy.
Also, for good practice, let's inform the flutter version that was used to build the engine binary, by updating the `flutter.version` file.

Windows:

- `flutter_engine.dll`
- `flutter_engine.dll.lib`
- `icudtl.dat`
- `embedder.vcxproj`

```sh
cd ../../../.. # Go to the root of the project
mkdir -p clib/lib/windows-x64/
cp .fvm/flutter_sdk/engine/src/out/host_release/flutter_engine.dll clib/lib/windows-x64/
cp .fvm/flutter_sdk/engine/src/out/host_release/flutter_engine.dll.lib clib/lib/windows-x64/
cp .fvm/flutter_sdk/engine/src/out/host_release/icudtl.dat clib/lib/windows-x64/
cp .fvm/flutter_sdk/bin/cache/flutter.version.json clib/lib/windows-x64/flutter.version.json
```

MacOS:

- `libflutter_engine.dylib`
- `icudtl.dat`
- `FlutterEmbedder.framework`

```sh
cd ../../../.. # Go to the root of the project
mkdir -p clib/lib/macos-arm64/
cp .fvm/flutter_sdk/engine/src/out/host_release/libflutter_engine.dylib clib/lib/macos-arm64/
cp .fvm/flutter_sdk/engine/src/out/host_release/icudtl.dat clib/lib/macos-arm64/
cp -r .fvm/flutter_sdk/engine/src/out/host_release/FlutterEmbedder.framework clib/lib/macos-arm64/
cp .fvm/flutter_sdk/bin/cache/flutter.version.json clib/lib/macos-arm64/flutter.version.json
```

## Build the project binary

Now let's build the project!
With the engine built, we can build the project binary.
Open a terminal on the root of the project, then run:

```sh
cd clib
./build.sh
```
