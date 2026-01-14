os=$(uname -s)
arch=$(uname -m)

case "$os" in
    Darwin)
        os_str="macos"
        ;;
    Linux)
        os_str="linux"
        ;;
    CYGWIN*|MINGW*|MSYS*)
        os_str="windows"
        ;;
    *)
        os_str="unknown"
        ;;
esac

case "$arch" in
    x86_64|amd64)
        arch_str="amd64"
        ;;
    arm64|aarch64)
        arch_str="arm64"
        ;;
    i386|i686)
        arch_str="386"
        ;;
    *)
        arch_str="$arch"
        ;;
esac

osarch="${os_str}-${arch_str}"

echo "Building for ${osarch}"
echo "Removing build/${osarch}"

rm -rf build/${osarch}
mkdir -p build/${osarch}

echo "Copying assets to build/${osarch}"

cp -r ../assets build/${osarch}/
cp -r lib/${osarch} build/

echo "Assembling flutter assets"

cd ../
flutter build bundle --release --asset-dir=clib/build/${osarch}/flutter_assets
flutter assemble --output=clib/build/${osarch} -dTargetPlatform=darwin -dDarwinArchs=arm64 -dBuildMode=release -dTreeShakeIcons=true release_macos_bundle_flutter_assets
if [ $? -ne 0 ]; then
    echo "Failed to assemble flutter assets"
    exit 1
fi

cd clib/build/${osarch}

echo "Building embedder (running cmake)"

cmake ../..

echo "Building embedder (running make)"
make

echo "Cleaning up"
rm cmake_install.cmake
rm -rf CMakeFiles
rm Makefile
rm CMakeCache.txt
rm -rf *.dSYM
rm .last_build_id

echo "Running embedder"

./embedder