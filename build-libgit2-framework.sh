# Build libgit2 XCFramework
#
# This script assumes that
#  1. it is run at the root of the repo
#  2. the required tools (wget, ninja, cmake, autotools) are installed either globally via homebrew or locally in tools/bin using our other script build_tools.sh
#

export REPO_ROOT=`pwd`
export PATH=$PATH:$REPO_ROOT/tools/bin

# openssl off
export OPENSSL_ROOT_DIR=""
export OPENSSL_LIBRARIES=""
export OPENSSL_INCLUDE_DIR=""
unset OPENSSL_ROOT_DIR
unset PKG_CONFIG_PATH

# List of platforms-architecture that we support
# Note that there are limitations in `xcodebuild` command that disallows `maccatalyst` and `macosx` (native macOS lib) in the same xcframework.
AVAILABLE_PLATFORMS=(iphoneos iphonesimulator iphonesimulator-arm64 maccatalyst maccatalyst-arm64) # macosx macosx-arm64

# List of frameworks included in the XCFramework (= AVAILABLE_PLATFORMS without architecture specifications)
XCFRAMEWORK_PLATFORMS=(iphoneos iphonesimulator maccatalyst)

# List of platforms that need to be merged using lipo due to presence of multiple architectures
LIPO_PLATFORMS=(iphonesimulator maccatalyst)

### Setup common environment variables to run CMake for a given platform
### Usage:      setup_variables PLATFORM
### where PLATFORM is the platform to build for and should be one of
###    iphoneos  (implicitly arm64)
###    iphonesimulator, iphonesimulator-arm64
###    maccatalyst, maccatalyst-arm64
###    macosx, macosx-arm64
###
### After this function is executed, the variables
###    $PLATFORM
###    $ARCH
###    $SYSROOT
###    $CMAKE_ARGS
### providing basic/common CMake options will be set.
function setup_variables() {
	cd $REPO_ROOT
	PLATFORM=$1

	CMAKE_ARGS=(-DBUILD_SHARED_LIBS=NO \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_COMPILER_WORKS=ON \
		-DCMAKE_CXX_COMPILER_WORKS=ON \
		-DCMAKE_INSTALL_PREFIX=$REPO_ROOT/install/$PLATFORM)

	case $PLATFORM in
		"iphoneos")
			ARCH=arm64
			SYSROOT=`xcodebuild -version -sdk iphoneos Path`
			CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES=$ARCH \
				-DCMAKE_OSX_SYSROOT=$SYSROOT);;

		"iphonesimulator")
			ARCH=x86_64
			SYSROOT=`xcodebuild -version -sdk iphonesimulator Path`
			CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_SYSROOT=$SYSROOT);;

		"iphonesimulator-arm64")
			ARCH=arm64
			SYSROOT=`xcodebuild -version -sdk iphonesimulator Path`
			CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_SYSROOT=$SYSROOT);;

		"maccatalyst")
			ARCH=x86_64
			SYSROOT=`xcodebuild -version -sdk macosx Path`
			CMAKE_ARGS+=(-DCMAKE_C_FLAGS=-target\ $ARCH-apple-ios14.1-macabi);;

		"maccatalyst-arm64")
			ARCH=arm64
			SYSROOT=`xcodebuild -version -sdk macosx Path`
			CMAKE_ARGS+=(-DCMAKE_C_FLAGS=-target\ $ARCH-apple-ios14.1-macabi);;

		"macosx")
			ARCH=x86_64
			SYSROOT=`xcodebuild -version -sdk macosx Path`;;

		"macosx-arm64")
			ARCH=arm64
			SYSROOT=`xcodebuild -version -sdk macosx Path`
			CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES=$ARCH);;

		*)
			echo "Unsupported or missing platform! Must be one of" ${AVAILABLE_PLATFORMS[@]}
			exit 1;;
	esac
}

### Build libpcre for a given platform
function build_libpcre() {
	setup_variables $1

	rm -rf pcre-8.45
	git clone https://github.com/light-tech/PCRE.git pcre-8.45
	cd pcre-8.45

	rm -rf build && mkdir build && cd build
	CMAKE_ARGS+=(-DPCRE_BUILD_PCRECPP=NO \
		-DPCRE_BUILD_PCREGREP=NO \
		-DPCRE_BUILD_TESTS=NO \
		-DPCRE_SUPPORT_LIBBZ2=NO)

	cmake "${CMAKE_ARGS[@]}" .. >/dev/null 2>/dev/null

	cmake --build . --target install >/dev/null 2>/dev/null
}

### Build mbedtls for a given platform
function build_mbedtls() {
	setup_variables $1

	# It is better to remove and redownload the source since building make the source code directory dirty!
	rm -rf mbedtls-3.6.3.1
	test -f v3.6.3.1.tar.gz || wget -q https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/v3.6.3.1.tar.gz
	tar xzf v3.6.3.1.tar.gz
	cd mbedtls-3.6.3.1

	case $PLATFORM in
		"iphoneos")
			TARGET_OS=ios64-cross
			export CFLAGS="-isysroot $SYSROOT -arch $ARCH";;

		"iphonesimulator"|"iphonesimulator-arm64")
			TARGET_OS=iossimulator-xcrun
			export CFLAGS="-isysroot $SYSROOT -arch $ARCH";;

		"maccatalyst"|"maccatalyst-arm64")
			TARGET_OS=darwin64-$ARCH-cc
			export CFLAGS="-isysroot $SYSROOT -target $ARCH-apple-ios14.1-macabi";;

		"macosx"|"macosx-arm64")
			TARGET_OS=darwin64-$ARCH-cc
			export CFLAGS="-isysroot $SYSROOT";;

		*)
			echo "Unsupported or missing platform!";;
	esac

	# See https://wiki.openssl.org/index.php/Compilation_and_Installation
	cmake -S . -B "$REPO_ROOT/install/$PLATFORM" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT=$SYSROOT \
    -DCMAKE_OSX_ARCHITECTURES=$ARCH \
    -DCMAKE_INSTALL_PREFIX=$REPO_ROOT/install/$PLATFORM \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_PROGRAMS=OFF \
    -DENABLE_TESTING=OFF
    echo "=== mbedTLS Build ==="
    cmake --build "$REPO_ROOT/install/$PLATFORM" --config Release
    cmake --install "$REPO_ROOT/install/$PLATFORM"
    
    echo "=== mbedTLS Build Result ==="
    ls -la $REPO_ROOT/install/$PLATFORM/library/libmbed*.a || echo "mbedTLS build failed - no libraries created!"
	export -n CFLAGS
}

### Build libssh2 for a given platform (assume mbedtls was built)
function build_libssh2() {
	setup_variables $1

	rm -rf libssh2-1.11.1
	test -f libssh2-1.11.1.tar.gz || wget -q https://www.libssh2.org/download/libssh2-1.11.1.tar.gz
	tar xzf libssh2-1.11.1.tar.gz
	cd libssh2-1.11.1

	rm -rf build && mkdir build && cd build

	CMAKE_ARGS+=(-DCRYPTO_BACKEND=mbedTLS \
		-DUSE_MBEDTLS=ON \
		-DMBEDTLS_INCLUDE_DIR=$REPO_ROOT/install/$PLATFORM/include \
		-DMBEDTLS_LIBRARY=$REPO_ROOT/install/$PLATFORM/library/libmbedtls.a \
		-DMBEDCRYPTO_LIBRARY=$REPO_ROOT/install/$PLATFORM/library/libmbedcrypto.a \
		-DMBEDX509_LIBRARY=$REPO_ROOT/install/$PLATFORM/library/libmbedx509.a \
		-DBUILD_EXAMPLES=OFF \
		-DBUILD_TESTING=OFF)

	echo "=== libssh2 CMake Configuration ==="
	cmake "${CMAKE_ARGS[@]}" ..

	echo "=== libssh2 Build ==="
	cmake --build . --target install

	echo "=== Checking libssh2 result ==="
	ls -la $REPO_ROOT/install/$PLATFORM/lib/libssh2.a || echo "libssh2.a not created!"
	ls -la $REPO_ROOT/install/$PLATFORM/include/libssh2.h || echo "libssh2 headers not found!"
}

### Build libgit2 for a single platform (given as the first and only argument)
### See @setup_variables for the list of available platform names
### Assume openssl and libssh2 was built
function build_libgit2() {
    setup_variables $1

    rm -rf libgit2-1.3.1
    test -f v1.3.1.zip || wget -q https://github.com/libgit2/libgit2/archive/refs/tags/v1.3.1.zip
    ditto -V -x -k --sequesterRsrc --rsrc v1.3.1.zip ./ >/dev/null 2>/dev/null
    cd libgit2-1.3.1

    rm -rf build && mkdir build && cd build

    CMAKE_ARGS+=(-DBUILD_CLAR=NO)

    echo "=== Debugging libgit2 dependencies ==="
    echo "Checking libssh2:"
    ls -la $REPO_ROOT/install/$PLATFORM/lib/libssh2.a || echo "libssh2.a missing!"
    echo "Checking mbedTLS:"
    ls -la $REPO_ROOT/install/$PLATFORM/library/libmbed*.a || echo "mbedTLS libraries missing!"
    echo "Checking all libraries:"
    ls -la $REPO_ROOT/install/$PLATFORM/lib/
    ls -la $REPO_ROOT/install/$PLATFORM/library/

    # See libgit2/cmake/FindPkgLibraries.cmake to understand how libgit2 looks for libssh2
    # Basically, setting LIBSSH2_FOUND forces SSH support and since we are building static library,
    # we only need the headers.
    CMAKE_ARGS+=(-DUSE_SSH=ON \
        -DCMAKE_PREFIX_PATH=$REPO_ROOT/install/$PLATFORM \
        -DLIBSSH2_ROOT=$REPO_ROOT/install/$PLATFORM \
        -DUSE_MBEDTLS=ON \
        -DMBEDTLS_ROOT_DIR=$REPO_ROOT/install/$PLATFORM \
        -DUSE_OPENSSL=OFF \
        -DOpenSSL_FOUND=NO \
        -DOPENSSL_FOUND=NO \
        -DOPENSSL_ROOT_DIR="" \
        -DOPENSSL_INCLUDE_DIR="" \
        -DOPENSSL_CRYPTO_LIBRARY="" \
        -DOPENSSL_SSL_LIBRARY="" \
        -DOPENSSL_LIBRARIES="" \
        -DPKG_CONFIG_EXECUTABLE="" \
        -DUSE_PKG_CONFIG=OFF)

    echo "=== libgit2 CMake Configuration ==="
    cmake "${CMAKE_ARGS[@]}" ..

    echo "=== libgit2 Build ==="
    cmake --build . --target install
}

### Create xcframework for a given library
function build_xcframework() {
	local FWNAME=$1
	shift
	local PLATFORMS=( "$@" )
	local FRAMEWORKS_ARGS=()

	echo "Building" $FWNAME "XCFramework containing" ${PLATFORMS[@]}

	for p in ${PLATFORMS[@]}; do
		FRAMEWORKS_ARGS+=("-library" "install/$p/$FWNAME.a" "-headers" "install/$p/include")
	done

	cd $REPO_ROOT
	xcodebuild -create-xcframework ${FRAMEWORKS_ARGS[@]} -output $FWNAME.xcframework
}

### Copy SwiftGit2's module.modulemap to libgit2.xcframework/*/Headers
### so that we can use libgit2 C API in Swift (e.g. via SwiftGit2)
function copy_modulemap() {
    local FWDIRS=$(find Clibgit2.xcframework -mindepth 1 -maxdepth 1 -type d)
    for d in ${FWDIRS[@]}; do
        echo $d
        cp Clibgit2_modulemap $d/Headers/module.modulemap
    done
}

### Build libgit2 and Clibgit2 frameworks for all available platforms

for p in ${AVAILABLE_PLATFORMS[@]}; do
	echo "Build libraries for $p"
	build_libpcre $p
	build_mbedtls $p
	build_libssh2 $p
	build_libgit2 $p

	# Merge all static libs as libgit2.a since xcodebuild doesn't allow specifying multiple .a
	cd $REPO_ROOT/install/$p
	libtool -static -o libgit2.a lib/*.a library/*.a
done

# Merge the libgit2.a for iphonesimulator & iphonesimulator-arm64 as well as maccatalyst & maccatalyst-arm64 using lipo
for p in ${LIPO_PLATFORMS[@]}; do
    cd $REPO_ROOT/install/$p
    lipo libgit2.a ../$p-arm64/libgit2.a -output libgit2_all_archs.a -create
    test -f libgit2_all_archs.a && rm libgit2.a && mv libgit2_all_archs.a libgit2.a
done

# Build raw libgit2 XCFramework for Objective-C usage
build_xcframework libgit2 ${XCFRAMEWORK_PLATFORMS[@]}
zip -r libgit2.xcframework.zip libgit2.xcframework/

# Build Clibgit2 XCFramework for use with SwiftGit2
mv libgit2.xcframework Clibgit2.xcframework
copy_modulemap
zip -r Clibgit2.xcframework.zip Clibgit2.xcframework/
