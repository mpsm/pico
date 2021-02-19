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

# default values of setup settings
: ${PICO_TOOLCHAIN_PATH="${HOME}/toolchain/${PICO_TOOLCHAIN_NAME}"}
: ${PICO_REPO_PATH="${HOME}/pico"}
: ${PICO_BINARY_PATH="${HOME}/.local/bin"}

# various helper methods
check_binary() {
    binary_name=$1
    which ${binary_name} > /dev/null
    return $?
}

declare -a pico_install_steps
declare -a debs_to_install

setup_install_step() {
    # setup user-friendly name
    if [ ! -z $3 ]; then
        name="$3"
    else
        name="$1"
    fi

    # check binary existence in the system
    if check_binary $1; then
        found=1
    else
        found=0
    fi

    # get user decision
    while :; do
        echo -n "Install $name?"
        if [ $found -ne 1 ]; then
            echo -n "[Y/n"
        else
            echo -n " Found at: $(dirname $(which $1)) [y/N"
        fi
        echo -n "] "

        read userinput
        if [ -z "$userinput" ]; then
            decision=$((1-$found))
            break
        fi

        case "$userinput" in
        [Yy])
            decision=1
            break
            ;;
        [Nn])
            decision=0
            break
            ;;
        esac
    done
    
    # add install step if decision is positive
    if [ $decision -eq 1 ]; then
        if [ ! -z "$2" ]; then
            echo -n "Install path for $name [$2]: "
            read userinput
            if [ -z "${userinput}" ]; then
                path=$2
            else
                path=${userinput}
            fi
            pico_install_steps+=("install_$name $path")
        else
            pico_install_steps+=("install_$name")
        fi
        readonly install_$name=1
    else
        readonly install_$name=0
    fi

    return $decision
}

# setup install steps
setup_install_step ${PICO_TOOLCHAIN_NAME}-gcc ${PICO_TOOLCHAIN_PATH} "toolchain"
setup_install_step openocd ${PICO_BINARY_PATH}
setup_install_step picotool ${PICO_BINARY_PATH}
setup_install_step code

if [ $install_code -eq 1 ]; then
    debs_to_install+=("code")
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

    # look for the required tools, build list of packages to install
    for package in "${pico_packages[@]}"
    do
        read binary package_name <<< $package
        echo -n "Checking for application: $binary ... "
        if check_binary $binary; then
            echo "found"
        else
            echo "not found"
            debs_to_install+=(${package_name})
        fi
    done

    # TODO - refactor library checking
    # check for libusb
    if [ $(apt -qq list libusb-1.0-0-dev 2>/dev/null | grep installed | wc -l) -eq 0 ]; then
        debs_to_install+=(libusb-1.0-0-dev)
    fi

    # check for hidapi
    if [ $(apt -qq list libhidapi-dev 2>/dev/null | grep installed | wc -l) -eq 0 ]; then
        debs_to_install+=(libhidapi-dev)
    fi

    # install packages with tools that were not found
    if [ ${#debs_to_install[*]} -eq 0 ]; then
        echo "All required tools found, skipping."
    else
        echo "Installing: ${debs_to_install[*]}"
        set -x
        sudo apt-get install -qq --yes ${debs_to_install[*]}
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
