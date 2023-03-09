#!/bin/bash

WINDOWS_URL="https://download.zerotier.com/dist/ZeroTier%20One.msi"
MACOS_URL="https://download.zerotier.com/dist/ZeroTier%20One.pkg"
UBUNTU22_URL="https://download.zerotier.com/debian/jammy/pool/main/z/zerotier-one/"
UBUNTU20_URL="https://download.zerotier.com/debian/focal/pool/main/z/zerotier-one/"
UBUNTU_FILE_PATTERN='zerotier-one_(.*?)_amd64.deb'

set -e -o pipefail
SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRIPTS_DIR=$(realpath $SCRIPTS_DIR)
ROOT_DIR=$(realpath $SCRIPTS_DIR/..)
TMP_DIR=$(realpath $SCRIPTS_DIR/tmp)

source $SCRIPTS_DIR/version.sh

mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

if wget --version > /dev/null 2>&1; then
    DOWNLOAD="wget -O"
else
    DOWNLOAD="curl --output"
fi

echo $DOWNLOAD

function ubuntu {
    mkdir -p $1
    pushd $1
    # Download index and find latest version
    URL_NAME=UBUNTU${1}_URL
    URL=${!URL_NAME}
    [ -e a.html ] || $DOWNLOAD a.html "$URL"
    LATEST=$(python $SCRIPTS_DIR/find-latest.py a.html "$UBUNTU_FILE_PATTERN")
    # Download DEB package
    [ -e a.deb ] || $DOWNLOAD a.deb "$URL/$LATEST"
    # Extract data from the package
    ar x a.deb
    [ -e data.tar.xz ] && tar -xJf data.tar.xz
    [ -e data.tar.zst ] && tar --zstd -xf data.tar.zst
    # Check version
    ACTUAL_VERSION=`usr/sbin/zerotier-one -v`
    if [ "$EXPECTED_VERSION" != "$ACTUAL_VERSION" ]; then
        echo Invalid version
        echo Expected: $EXPECTED_VERSION
        echo Actual:   $ACTUAL_VERSION
        exit 1
    fi
    # Output only essential files
    pushd usr/sbin
    XZ_OPT="-7e" tar -cJf $TMP_DIR/ubuntu-$1.tar.xz *
    popd
    popd
}

function windows {
    mkdir -p win
    pushd win
    # Download Windows MSI
    [ -e a.msi ] || $DOWNLOAD a.msi "$WINDOWS_URL"
    # Prepare extraction directory
    rm -Rf bin
    TARGETDIR=$(realpath ./bin)
    MSYS2_ARG_CONV_EXCL=/c cmd /c echo $TARGETDIR > t.txt
    TARGETDIR=$(cat t.txt)
    TARGETDIR=${TARGETDIR//\//\\}
    # Run msiexec to extract files
    MSYS2_ARG_CONV_EXCL="/a;/qb" msiexec /a a.msi /qb TARGETDIR=$TARGETDIR
    # TODO: on target Move files to C:\ProgramData\ZeroTier\One and copy zerotier-one_x64.exe to zerotier-cli, zerotier-idtool   
    # Copy only essential files for x64 target
    mkdir -p out/ZeroTier/One/tap-windows/x64
    cp bin/CommonAppDataFolder/ZeroTier/One/tap-windows/x64/* out/ZeroTier/One/tap-windows/x64/
    cp bin/CommonAppDataFolder/ZeroTier/One/zerotier-one_x64.exe out/ZeroTier/One/
    # Check version
    ACTUAL_VERSION=`out/ZeroTier/One/zerotier-one_x64.exe -v`
    if [ "$EXPECTED_VERSION" != "$ACTUAL_VERSION" ]; then
        echo Invalid version
        echo Expected: $EXPECTED_VERSION
        echo Actual:   $ACTUAL_VERSION
        exit 1
    fi
    # Compress output
    pushd out
    XZ_OPT="-7e" tar -cJf $TMP_DIR/windows.tar.xz *
    popd
    popd
}

$1 $2

# TODO: Automated workflow on shedule:
# 1. Detect the latest version update (based on latest ubuntu file name).
# 2. Wait 47h to be sure that all OSes are updated
# 3. Create branch update-x.y.z and push new expected version number to version.sh
# 4. Build distribution archives
# 5. Run tests on the branch
# 6. Create PR with the changes
# 7. Merge PR
# 8. Create release draft and attach distribution archives

# PR and push to main tests:
# 1. If expected version != latest release, build distribution archives and use it,
#    otherwise use release attachments.
# 2. Run tests on the branch:
#    * Run in parallel all OSes two times:
#       1) with different, but predefined identity,
#       2) with autogenerated identity (accepting over REST API will be required)
#    * Use REST API to query the IP addresses
#    * Exchange some messages between each of them (ping and one sec. iperf)
#      "iperf -c [ADDR] -t 1" "ping -c 3 -W 5 [ADDR]"

# Use different identities for PR, push to main and release/automated release to prevent conflicts.
# Use https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#concurrency
# to prevent identity conflicts.
