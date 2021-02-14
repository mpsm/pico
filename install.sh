#!/usr/bin/bash

# local variables
PICO_TOOLCHAIN_NAME="arm-none-eabi"
PICO_TOOLCHAIN_LINK="https://developer.arm.com/-/media/Files/downloads/gnu-rm/10-2020q4/gcc-arm-none-eabi-10-2020-q4-major-x86_64-linux.tar.bz2"
PICO_TOOLCHAIN_VERSION="gcc-arm-none-eabi-10-2020-q4-major"

# setup installation steps
which ${PICO_TOOLCHAIN_NAME}-gcc > /dev/null
if [ $? -ne 0 ]; then
    PICO_INSTALL_TOOLCHAIN=1
fi

# default values of setup settings
: ${PICO_TOOLCHAIN_PATH="${HOME}/toolchain/${PICO_TOOLCHAIN_NAME}"}

# setup
if [ ! -z ${PICO_INSTALL_TOOLCHAIN} ]; then
    echo -n "Path to install the toolchain to [${PICO_TOOLCHAIN_PATH}]: "
    read userinput
    if [ ! -z ${userinput} ]; then
        PICO_TOOLCHAIN_PATH="${userinput}"
    fi
fi

# installation helper methods
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
    if [ $(grep '${bindir}' '${HOME}/.bashrc' | wc -l)  -eq 0 ]; then
        echo "export PATH=\"${bindir}:\$PATH\"" >> ${HOME}/.bashrc
    fi
    
    export PATH="${bindir}:${PATH}"
    echo "Tolchain installation done."
}

# installation process
if [ ! -z ${PICO_INSTALL_TOOLCHAIN} ]; then
    install_toolchain
fi

echo "Finished. Re-login to refresh environmental variables."
