#!/usr/bin/bash

# check if executing from the repository
scriptname="$(basename $0)"
if [ ${scriptname} == "bash" ]; then
    PICO_CLONE_REPO=1
else
    if [ ! -d "$(dirname $0)/.git" ]; then
        PICO_CLONE_REPO=1
    else
        PICO_REPO_PATH="$(realpath $(dirname $0))"
    fi
fi

# local variables
PICO_REPO_URL="https://github.com/mpsm/pico"
PICO_TOOLCHAIN_NAME="arm-none-eabi"
PICO_TOOLCHAIN_LINK="https://developer.arm.com/-/media/Files/downloads/gnu-rm/10-2020q4/gcc-arm-none-eabi-10-2020-q4-major-x86_64-linux.tar.bz2"
PICO_TOOLCHAIN_VERSION="gcc-arm-none-eabi-10-2020-q4-major"

# various helper methods
check_binary() {
    binary_name=$1
    which ${binary_name} > /dev/null
    return $?
}

# setup installation steps
if ! check_binary ${PICO_TOOLCHAIN_NAME}-gcc; then
    PICO_INSTALL_TOOLCHAIN=1
else
    echo "Found toolchain at: $(dirname $(which ${PICO_TOOLCHAIN_NAME}-gcc)), skipping toolchain install."
fi

if ! check_binary picotool; then
    PICO_INSTALL_PICOTOOL=1
else
    echo "Found picotool ($(which picotool)), skipping."
fi

if ! check_binary openocd; then
    PICO_INSTALL_OPENOCD=1
else
    echo "Found openocd $(which openocd)), skipping."
fi

# default values of setup settings
: ${PICO_TOOLCHAIN_PATH="${HOME}/toolchain/${PICO_TOOLCHAIN_NAME}"}
: ${PICO_REPO_PATH="${HOME}/pico"}
: ${PICO_BINARY_PATH="${HOME}/.local/bin"}

# setup
if [ ! -z ${PICO_CLONE_REPO} ]; then
    echo -n "Path to install the SDK to [${PICO_REPO_PATH}]: "
    read userinput
    if [ ! -z ${userinput} ]; then
        PICO_REPO_PATH="${userinput}"
    fi
fi
if [ -d ${PICO_REPO_PATH} ]; then
    echo "Directory ${PICO_REPO_PATH} not empty, skipping clone."
fi

if [ ! -z ${PICO_INSTALL_TOOLCHAIN} ]; then
    echo -n "Path to install the toolchain to [${PICO_TOOLCHAIN_PATH}]: "
    read userinput
    if [ ! -z ${userinput} ]; then
        PICO_TOOLCHAIN_PATH="${userinput}"
    fi
fi

if [ ! -z ${PICO_INSTALL_PICOTOOL} ]; then
    echo -n "Path to install tools to [${PICO_BINARY_PATH}]: "
    read userinput
    if [ ! -z ${userinput} ]; then
        PICO_BINARY_PATH=${userinput}
    fi
fi

if [ ! -d ${PICO_BINARY_PATH} ]; then
    mkdir -p ${PICO_BINARY_PATH}
fi

# installation helper methods
install_packages() {
    echo "Checking for required packages"

    declare -a pico_packages=(
        "cmake cmake"
        "gcc build-essential"
        "git git"
        "ninja ninja-build"
    )
    declare -a to_install

    # look for the required tools, build list of packages to install
    for package in "${pico_packages[@]}"
    do
        read binary package_name <<< $package
        echo -n "Checking for application: $binary ... "
        if check_binary $binary; then
            echo "found"
        else
            echo "not found"
            to_install+=(${package_name})
        fi
    done

    # TODO - refactor library checking
    # check for libusb
    if [ $(apt -qq list libusb-1.0-0-dev 2>/dev/null | grep installed | wc -l) -eq 0 ]; then
        to_install+=(libusb-1.0-0-dev)
    fi

    # check for hidapi
    if [ $(apt -qq list libhidapi-dev 2>/dev/null | grep installed | wc -l) -eq 0 ]; then
        to_install+=(libhidapi-dev)
    fi

    # install packages with tools that were not found
    if [ ${#to_install[*]} -eq 0 ]; then
        echo "All required tools found, skipping."
    else
        echo "Installing: ${to_install[*]}"
        set -x
        sudo apt-get install -qq --yes ${to_install[*]}
        set +x
    fi
}

install_toolchain() {
    echo "Installing the toolchain... "
    if [ ! -d ${PICO_TOOLCHAIN_PATH} ]; then
        echo "Creating toolchain dir: ${PICO_TOOLCHAIN_PATH}"
        mkdir -p ${PICO_TOOLCHAIN_PATH}
    fi

    if [ ! -d "${PICO_TOOLCHAIN_PATH}/${PICO_TOOLCHAIN_VERSION}" ]; then
        echo "Downloading the toolchain"
        cd ${PICO_TOOLCHAIN_PATH} && wget --no-verbose --show-progress -O- ${PICO_TOOLCHAIN_LINK} | tar xj
    fi

    echo "Tolchain installation done."
}

setup_paths()
{
    echo "Setting up paths"

    bindir="${PICO_TOOLCHAIN_PATH}/${PICO_TOOLCHAIN_VERSION}/bin"
    export PATH="${bindir}:${PATH}"
    export PICO_SDK_PATH="${PICO_REPO_PATH}/sdk"

    case ${SHELL} in
        */fish)
            fishconfd="${HOME}/.config/fish/conf.d"
            if [ ! -d ${fishconfd} ]; then
                mkdir -p ${fishconfd}
            fi
            
            fishconfig="${fishconfd}/pico.fish"
            if [ ! -f ${fishconfig} ]; then
                echo "set -g -x PATH \$PATH \"${bindir}\"" > ${fishconfig}
                echo "set -g -x PICO_SDK_PATH \"${PICO_SDK_PATH}\"" >> ${fishconfig}
            fi
            ;;
    esac

    # install bash anyway
    if [ $(grep "${bindir}" "${HOME}/.bashrc" | wc -l) -eq 0 ]; then
        echo "export PATH=\"${bindir}:\$PATH\"" >> ${HOME}/.bashrc
    fi

    if [ $(grep PICO_SDK_PATH "${HOME}/.bashrc" | wc -l) -eq 0 ]; then
        echo "export PICO_SDK_PATH=\"${PICO_SDK_PATH}\"" >> ${HOME}/.bashrc
    fi
}

build() {
    target=$1

    echo "Building ${target}"
    cmake -S ${PICO_REPO_PATH}/${target} -B ${PICO_REPO_PATH}/build/${target} -G Ninja && cmake --build ${PICO_REPO_PATH}/build/${target}
}

# installation process - check for packages
install_packages

# clone the repo
if [ ! -z ${PICO_CLONE_REPO} ]; then
    echo "Cloning the bundle repository"
    git clone --recurse-submodules ${PICO_REPO_URL} ${PICO_REPO_PATH}
else
    # make sure submodules are up to date
    echo "Making sure submodules are up to date"
    git submodule update --init --recursive
fi

# setup paths
setup_paths

# install toolchain
if [ ! -z ${PICO_INSTALL_TOOLCHAIN} ]; then
    install_toolchain
fi

# build examples
if [ ! -d ${PICO_REPO_PATH}/uf2/examples ]; then
    build examples
    mkdir -p ${PICO_REPO_PATH}/uf2/examples
    find ${PICO_REPO_PATH}/build/examples -name "*.uf2" | xargs -I"{}" cp "{}" ${PICO_REPO_PATH}/uf2/examples
else
    echo "Found examples dir, skipping."
fi

# build tools
if [ ! -z ${PICO_INSTALL_PICOTOOL} ]; then
    if [ -f ${PICO_BINARY_PATH}/picotool ]; then
        echo "Picotool exists at installation path, skipping."
    else
        build picotool
        cp ${PICO_REPO_PATH}/build/picotool/picotool ${PICO_BINARY_PATH}
    fi
fi

# build picoprobe
if [ ! -f ${PICO_REPO_PATH}/uf2/picoprobe.uf2 ]; then
    build picoprobe
    mkdir -p ${PICO_REPO_PATH}/uf2/
    cp ${PICO_REPO_PATH}/build/picoprobe/picoprobe.uf2 ${PICO_REPO_PATH}/uf2/
else
    echo "Picoprobe exists, skipping."
fi

# build and install openocd
if [ ! -z ${PICO_INSTALL_OPENOCD} ]; then
    openocd_install_path="$(dirname ${PICO_BINARY_PATH})"
    openocd_config="--enable-cmsis-dap --enable-picoprobe --prefix=${openocd_install_path}"
    openocd_path=${PICO_REPO_PATH}/openocd
    cd ${openocd_path} && ./bootstrap && ./configure ${openocd_config} && make -j $(nproc) && make install
fi
