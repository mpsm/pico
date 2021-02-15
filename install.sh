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

# default values of setup settings
: ${PICO_TOOLCHAIN_PATH="${HOME}/toolchain/${PICO_TOOLCHAIN_NAME}"}
: ${PICO_REPO_PATH="${HOME}/pico"}

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

    echo "Setting up toolchain path"
    bindir="${PICO_TOOLCHAIN_PATH}/${PICO_TOOLCHAIN_VERSION}//bin"
    case ${SHELL} in
        */fish)
            fishconfd="${HOME}/.config/fish/conf.d"
            if [ ! -d ${fishconfd} ]; then
                mkdir -p ${fishconfd}
            fi
            
            fishconfig="${fishconfd}/path-${PICO_TOOLCHAIN_NAME}.fish"
            if [ ! -f ${fishconfig} ]; then
                echo "set -g -x PATH \$PATH \"${bindir}\"" > ${fishconfd}/path-${PICO_TOOLCHAIN_NAME}.fish
            fi
            ;;
    esac

    # install bash anyway
    if [ $(grep "${bindir}" "${HOME}/.bashrc" | wc -l)  -eq 0 ]; then
        echo "export PATH=\"${bindir}:\$PATH\"" >> ${HOME}/.bashrc
    fi
    
    export PATH="${bindir}:${PATH}"
    echo "Tolchain installation done. You need to relogin."
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
export PICO_SDK_PATH="${PICO_REPO_PATH}/sdk"
PICO_EXAMPLES_PATH="${PICO_REPO_PATH}/examples"

# install toolchain
if [ ! -z ${PICO_INSTALL_TOOLCHAIN} ]; then
    install_toolchain
fi

# build examples
echo "Building examples"
cmake -S ${PICO_EXAMPLES_PATH} -B ${PICO_REPO_PATH}/build/examples -G Ninja && cmake --build ${PICO_REPO_PATH}/build/examples
mkdir -p uf2/examples
find ${PICO_REPO_PATH}/build/examples -name "*.uf2" | xargs -I"{}" cp "{}" uf2/examples
