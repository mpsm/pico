#!/usr/bin/bash

# local variables
PICO_REPO_URL="https://github.com/mpsm/pico"
PICO_TOOLCHAIN_NAME="arm-none-eabi"
PICO_TOOLCHAIN_LINK="https://developer.arm.com/-/media/Files/downloads/gnu-rm/10-2020q4/gcc-arm-none-eabi-10-2020-q4-major-x86_64-linux.tar.bz2"
PICO_TOOLCHAIN_VERSION="gcc-arm-none-eabi-10-2020-q4-major"

# default values of setup settings
: ${PICO_TOOLCHAIN_PATH="${HOME}/toolchain/${PICO_TOOLCHAIN_NAME}"}
: ${PICO_REPO_PATH="${HOME}/pico"}
: ${PICO_BINARY_PATH="${HOME}/.local/bin"}

# parse arguments
PARAMS=""
auto_mode=0
while (( "$#" )); do
    case "$1" in
        -a|--auto)
            auto_mode=1
            shift
            ;;
        -h|--help)
            echo "TODO: help"
            exit 0
            ;;
        *)
            PARAMS="${PARAMS} $1"
            shift
            ;;
    esac
done
eval set -- "${PARAMS}"

# check if executed in batch mode
if [[ $0 =~ bash ]]; then
    batch_mode=1
    auto_mode=1
else
    batch_mode=0
    if [ -z "$1" ]; then
        root_dir="$(dirname $(realpath $0))"
    else
        root_dir="$1"
    fi
fi

if [ $auto_mode ]; then
    echo "Executing in auto mode."
fi

repo_hash="d1a50566bc82612ac753b193bf74"
check_repo() {
    repodir="$1"
    dir_hash="$(cd $repodir && git log  --reverse --pretty="%h" 2>/dev/null | head -n 4 | tr -d '\n')"
    test "$repo_hash" = "$dir_hash"
}

check_binary() {
    binary_name=$1
    which ${binary_name} > /dev/null
    return $?
}

# installation helper methods
install_tools() {
    echo "Checking for required packages"

    declare -a debs_to_install
    declare -a pico_packages=(
        "cmake cmake"
        "gcc build-essential"
        "make build-essential"
        "git git"
        "ninja ninja-build"
        "wget wget"
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

    # install packages with tools that were not found
    if [ ${#debs_to_install[*]} -eq 0 ]; then
        echo "All required tools found, skipping."
    else
        echo "Installing: ${debs_to_install[*]}"
        set -x
        sudo apt update
        sudo apt-get install -qq --yes ${debs_to_install[*]}
        set +x
        readonly apt_updated=1
    fi
}

# install required tools
echo "Checking for required tools"
install_tools

# do we need to clone the repo?
if [ $batch_mode -eq 0 ] && check_repo $root_dir; then
    echo "Valid installation repository found at: $root_dir"
else
    echo -n "Where to clone the installation repository? [${PICO_REPO_PATH}]: "
    if [ $auto_mode -eq 1 ]; then
        echo ${PICO_REPO_PATH}
    else
        read userinput
        if [ -n "${userinput}" ]; then
            PICO_REPO_PATH="${userinput}"
        fi
    fi

    # sanity check
    if [ -e "${PICO_REPO_PATH}" ]; then
        echo "Repository exists, aborting."
        exit 1
    fi

    # clone the repo and execute newest version of the installation script
    echo "Cloning installation repository to: ${PICO_REPO_PATH}"
    git clone --recurse-submodules ${PICO_REPO_URL} ${PICO_REPO_PATH}
    if [ $? -eq 0 ]; then
        echo "Executing current installation script."
        if [ $batch_mode -eq 1 ]; then
            ${PICO_REPO_PATH}/install.sh --auto ${PICO_REPO_PATH}
        else
            ${PICO_REPO_PATH}/install.sh $* ${PICO_REPO_PATH}
        fi
    else
        echo "Clone failed, aborting."
        exit 2
    fi
fi

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
            echo -n " [Y/n"
        else
            echo -n " Found at: $(dirname $(which $1)) [y/N"
        fi
        echo -n "] "

        if [ $auto_mode -eq 1 ]; then
            if [ $found -eq 1 ]; then
                echo "N"
            else
                echo "Y"
            fi
        else
            read userinput
        fi

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
            if [ $auto_mode -eq 1 ]; then
                echo "$2"
            else
                read userinput
            fi
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

declare -a packages_to_install
assert_package_install() {
    package_name=$1
    # check for libusb
    if [ $(apt -qq list $package_name 2>/dev/null | grep installed | wc -l) -eq 0 ]; then
        packages_to_install+=($package_name)
    fi
}

cmd_install_toolchain() {
    echo "Installing the toolchain... "
    toolchain_path=$1
    if [ ! -d $toolchain_path ]; then
        echo "Creating toolchain dir: $toolchain_path"
        mkdir -p $toolchain_path
    fi

    if [ ! -d "$toolchain_path/${PICO_TOOLCHAIN_VERSION}" ]; then
        echo "Downloading the toolchain"
        cd $toolchain_path && wget --no-verbose --show-progress -O- ${PICO_TOOLCHAIN_LINK} | tar xj
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

cmd_install_code() {
    echo "Installing Visual Studio Code"
    
    # add repo if needed
    if [ $(grep -Er "^deb.*packages.microsoft.com/repos/code" /etc/apt/sources.list* | wc -l) -eq 0 ]; then
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
        set -x
        sudo install -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/trusted.gpg.d/
        sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
        sudo apt update
        set +x
    fi

    # install VSC using apt
    set -x
    sudo apt install code
    set +x
}

# check for https apt transport if installing code
if [ $install_code -eq 1 ]; then
    assert_package_install apt-transport-https
    assert_package_install gpg
fi

# install openocd's prerequisities
if [ $install_openocd ]; then
    assert_package_install libusb-1.0-0-dev
    assert_package_install libhidapi-dev
fi

# install packages if required
if [ ${#packages_to_install[@]} -gt 0 ]; then
    set -x
    if [ "${apt_updated}" != "1" ]; then
        sudo apt update
        readonly apt_updated=1
    fi
    sudo apt install -qq --yes ${debs_to_install[*]}
    set +x
fi

cmd_install_openocd() {
    echo "Installing openocd"
    openocd_install_path="$(dirname $1)"
    openocd_config="--enable-cmsis-dap --enable-picoprobe --prefix=${openocd_install_path}"
    openocd_path=${PICO_REPO_PATH}/openocd
    cd ${openocd_path} && ./bootstrap && ./configure ${openocd_config} && make -j $(nproc) && make install
}

cmd_install_picotool() {
    echo "Installing picotool"
    build picotool
    cp ${PICO_REPO_PATH}/build/picotool/picotool $1
}

# execute install steps
for step in "${pico_install_steps[@]}"
do
    read step_name path <<< $step
    echo "Executing install step: $step_name"
    cmd_$step_name $path
done

# setup paths
setup_paths

# build examples
if [ ! -d ${PICO_REPO_PATH}/uf2/examples ]; then
    build examples
    mkdir -p ${PICO_REPO_PATH}/uf2/examples
    find ${PICO_REPO_PATH}/build/examples -name "*.uf2" | xargs -I"{}" cp "{}" ${PICO_REPO_PATH}/uf2/examples
else
    echo "Found examples dir, skipping."
fi

# build picoprobe
if [ ! -f ${PICO_REPO_PATH}/uf2/picoprobe.uf2 ]; then
    build picoprobe
    mkdir -p ${PICO_REPO_PATH}/uf2/
    cp ${PICO_REPO_PATH}/build/picoprobe/picoprobe.uf2 ${PICO_REPO_PATH}/uf2/
else
    echo "Picoprobe exists, skipping."
fi
