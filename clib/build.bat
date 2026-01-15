@echo off
setlocal enabledelayedexpansion

set os_str=windows

if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    set arch_str=x64
) else if "%PROCESSOR_ARCHITECTURE%"=="x86" (
    set arch_str=x86
) else if "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    set arch_str=arm64
) else (
    set arch_str=%PROCESSOR_ARCHITECTURE%
)

set osarch=%os_str%-%arch_str%

echo Building for %osarch%
echo Removing build\%osarch%

if exist build\%osarch% rmdir /s /q build\%osarch%
mkdir build\%osarch%

echo Copying assets to build\%osarch%

xcopy /e /i /y ..\assets build\%osarch%\assets
xcopy /e /i /y lib\%osarch% build\%osarch%

echo Building flutter bundle

pushd ..
call fvm flutter build bundle --local-engine=host_release --local-engine-host=host_release --release --asset-dir=clib/build/%osarch%/flutter_assets
if %ERRORLEVEL% neq 0 (
    echo Failed to assemble flutter assets
    popd
    exit /b 1
)

echo Assembling flutter
call fvm flutter assemble --local-engine=host_release --local-engine-host=host_release --output=clib/build/%osarch% -dTargetPlatform=windows-%arch_str% -dTargetArchitecture=%arch_str% -dBuildMode=release -dTreeShakeIcons=true release_bundle_windows-%arch_str%_assets
if %ERRORLEVEL% neq 0 (
    echo Failed to assemble flutter
    popd
    exit /b 1
)
popd

cd build\%osarch%

echo Building embeddedFlutterApp (running cmake)

cmake ..\..

echo Building embeddedFlutterApp (running cmake --build)

cmake --build . --config Release

echo Cleaning up

if exist cmake_install.cmake del /q cmake_install.cmake
if exist CMakeFiles rmdir /s /q CMakeFiles
if exist x64 rmdir /s /q x64
if exist embeddedFlutterApp.dir rmdir /s /q embeddedFlutterApp.dir
if exist Makefile del /q Makefile
if exist CMakeCache.txt del /q CMakeCache.txt
if exist .last_build_id del /q .last_build_id
move Release\* .
rmdir /s /q Release
move windows\* .
rmdir /s /q windows
del /q *.vcxproj
del /q *.vcxproj.filters
del /q *.sln

echo Build complete!

echo The binary are located at %CD%\embeddedFlutterApp.exe
