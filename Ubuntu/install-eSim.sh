#!/bin/bash 
#=============================================================================
#          FILE: install-eSim.sh
# 
#         USAGE: ./install-eSim.sh --install 
#                            OR
#                ./install-eSim.sh --uninstall
#                
#   DESCRIPTION: Installation script for eSim EDA Suite
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#       AUTHORS: Fahim Khan, Rahul Paknikar, Saurabh Bansode,
#                Sumanto Kar, Partha Singha Roy
#  ORGANIZATION: eSim Team, FOSSEE, IIT Bombay
#       CREATED: Wednesday 15 July 2015 15:26
#      REVISION: Tuesday 31 December 2024 17:28
#=============================================================================

# All variables goes here
config_dir="$HOME/.esim"
config_file="config.ini"
eSim_Home=`pwd`
ngspiceFlag=0

## All Functions goes here

error_exit()
{
    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"
    exit 1
}

function createConfigFile
{
    # Creating config.ini file and adding configuration information
    # Check if config file is present
    if [ -d $config_dir ];then
        rm $config_dir/$config_file && touch $config_dir/$config_file
    else
        mkdir $config_dir && touch $config_dir/$config_file
    fi
    
    echo "[eSim]" >> $config_dir/$config_file
    echo "eSim_HOME = $eSim_Home" >> $config_dir/$config_file
    echo "LICENSE = %(eSim_HOME)s/LICENSE" >> $config_dir/$config_file
    echo "KicadLib = %(eSim_HOME)s/library/kicadLibrary.tar.xz" >> $config_dir/$config_file
    echo "IMAGES = %(eSim_HOME)s/images" >> $config_dir/$config_file
    echo "VERSION = %(eSim_HOME)s/VERSION" >> $config_dir/$config_file
    echo "MODELICA_MAP_JSON = %(eSim_HOME)s/library/ngspicetoModelica/Mapping.json" >> $config_dir/$config_file
}

function installNghdl
{
    echo "Installing NGHDL..........................."
    # Check if nghdl.zip exists before attempting to unzip
    if [ ! -f nghdl.zip ]; then
        echo "Error: nghdl.zip not found. Please make sure it exists in the current directory."
        return 1
    fi
    
    unzip -o nghdl.zip
    cd nghdl/
    chmod +x install-nghdl.sh

    # Do not trap on error of any command. Let NGHDL script handle its own errors.
    trap "" ERR

    ./install-nghdl.sh --install       # Install NGHDL
        
    # Set trap again to error_exit function to exit on errors
    trap error_exit ERR

    ngspiceFlag=1
    cd ../
}

function installSky130Pdk
{
    echo "Installing SKY130 PDK......................"
    
    # Check if SKY130 PDK archive exists before extracting
    if [ ! -f library/sky130_fd_pr.tar.xz ]; then
        echo "Error: SKY130 PDK archive not found at library/sky130_fd_pr.tar.xz"
        return 1
    fi
    
    # Extract SKY130 PDK
    tar -xJf library/sky130_fd_pr.tar.xz

    # Remove any previous sky130-fd-pdr instance, if any
    sudo rm -rf /usr/share/local/sky130_fd_pr

    # Copy SKY130 library
    echo "Copying SKY130 PDK........................."

    sudo mkdir -p /usr/share/local/
    sudo mv sky130_fd_pr /usr/share/local/

    # Change ownership from root to the user
    sudo chown -R $USER:$USER /usr/share/local/sky130_fd_pr/
}

function installKicad
{
    echo "Installing KiCad..........................."
    
    # Ubuntu 23.04 has KiCad 7.0 in its main repositories
    sudo apt-get install -y --no-install-recommends kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates

    # Check KiCad version and adjust configuration directory path
    kicad_version=$(apt-cache policy kicad | grep -oP 'Installed: \K[0-9]+\.[0-9]+' || echo "6.0")
    kicad_major_version=${kicad_version%%.*}
    
    # Set the KiCad config directory based on installed version
    echo "Detected KiCad version: $kicad_version (major: $kicad_major_version)"
    export KICAD_CONFIG_DIR="$HOME/.config/kicad/$kicad_major_version.0"
    echo "Using KiCad configuration directory: $KICAD_CONFIG_DIR"
}

function installDependency
{
    set +e
    trap "" ERR

    echo "Updating apt index files..................."
    sudo apt-get update

    set -e
    trap error_exit ERR

    echo "Installing virtualenv......................"
    sudo apt install -y python3-virtualenv

    echo "Creating virtual environment..............."
    virtualenv $config_dir/env

    echo "Starting the virtual environment..........."
    source $config_dir/env/bin/activate

    echo "Upgrading pip.............................."
    pip install --upgrade pip

    echo "Installing basic system packages..........."
    sudo apt-get install -y xterm python3-psutil python3-pyqt5 python3-matplotlib

    echo "Handling Python distutils dependency......."
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    PYTHON_MAJOR_MINOR=$(echo $PYTHON_VERSION | cut -d'.' -f1,2)
    echo "Detected Python version: $PYTHON_MAJOR_MINOR"

    # Check if distutils is available via Python
    if ! python3 -c "import distutils" &>/dev/null; then
        echo "distutils not found in standard library, installing setuptools in virtualenv..."
        pip install setuptools
    else
        echo "distutils is already available in Python."
    fi

    echo "Installing Pip3............................"
    sudo apt install -y python3-pip

    echo "Installing Python packages in virtualenv..."
    pip install setuptools matplotlib PyQt5 hdlparse watchdog makerchip-app sandpiper-saas

    echo "Installing Hdlparse........................"
    pip install --upgrade https://github.com/hdl/pyhdlparser/tarball/master
}

function copyKicadLibrary
{
    # Extract custom KiCad Library
    # Check if KiCad library archive exists
    if [ ! -f library/kicadLibrary.tar.xz ]; then
        echo "Error: KiCad library archive not found at library/kicadLibrary.tar.xz"
        return 1
    fi
    
    tar -xJf library/kicadLibrary.tar.xz

    # Use the KiCad configuration directory determined during installation
    if [ -d "$KICAD_CONFIG_DIR" ]; then
        echo "KiCad config folder already exists at $KICAD_CONFIG_DIR"
    else 
        echo "$KICAD_CONFIG_DIR does not exist"
        mkdir -p "$KICAD_CONFIG_DIR"
    fi

    # Copy symbol table for eSim custom symbols 
    cp kicadLibrary/template/sym-lib-table "$KICAD_CONFIG_DIR"/
    echo "Symbol table copied in the directory"

    # Check if symbols directory exists before copying
    if [ -d "kicadLibrary/eSim-symbols" ]; then
        # Create the symbols directory if it doesn't exist
        sudo mkdir -p /usr/share/kicad/symbols/
        # Copy KiCad symbols made for eSim
        sudo cp -r kicadLibrary/eSim-symbols/* /usr/share/kicad/symbols/
    else
        echo "Warning: eSim-symbols directory not found in kicadLibrary."
    fi

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command
    
    # Remove extracted KiCad Library - not needed anymore
    rm -rf kicadLibrary

    set -e      # Re-enable exit on error
    trap error_exit ERR

    # Change ownership from Root to the User
    sudo chown -R $USER:$USER /usr/share/kicad/symbols/
}

function createDesktopStartScript
{    
    # Generating new esim-start.sh
    echo '#!/bin/bash' > esim-start.sh
    echo "cd $eSim_Home/src/frontEnd" >> esim-start.sh
    echo "source $config_dir/env/bin/activate" >> esim-start.sh
    echo "python3 Application.py" >> esim-start.sh

    # Make it executable
    sudo chmod 755 esim-start.sh
    # Copy esim start script
    sudo cp -vp esim-start.sh /usr/bin/esim
    # Remove local copy of esim start script
    rm esim-start.sh

    # Generating esim.desktop file
    echo "[Desktop Entry]" > esim.desktop
    echo "Version=1.0" >> esim.desktop
    echo "Name=eSim" >> esim.desktop
    echo "Comment=EDA Tool" >> esim.desktop
    echo "GenericName=eSim" >> esim.desktop
    echo "Keywords=eda-tools" >> esim.desktop
    echo "Exec=esim %u" >> esim.desktop
    echo "Terminal=true" >> esim.desktop
    echo "X-MultipleArgs=false" >> esim.desktop
    echo "Type=Application" >> esim.desktop
    getIcon="$config_dir/logo.png"
    echo "Icon=$getIcon" >> esim.desktop
    echo "Categories=Development;" >> esim.desktop
    echo "MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;video/webm;application/x-xpinstall;" >> esim.desktop
    echo "StartupNotify=true" >> esim.desktop

    # Make esim.desktop file executable
    sudo chmod 755 esim.desktop
    # Copy desktop icon file to share applications
    sudo cp -vp esim.desktop /usr/share/applications/
    
    # Ensure Desktop directory exists before copying
    mkdir -p $HOME/Desktop/
    # Copy desktop icon file to Desktop
    cp -vp esim.desktop $HOME/Desktop/

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Make esim.desktop file as trusted application
    # Check if gio command exists before using it
    if command -v gio &> /dev/null; then
        gio set $HOME/Desktop/esim.desktop "metadata::trusted" true
    else
        echo "Warning: 'gio' command not found. Desktop icon may need manual trust setting."
    fi
    
    # Set Permission and Execution bit
    chmod a+x $HOME/Desktop/esim.desktop

    # Remove local copy of esim.desktop file
    rm esim.desktop

    set -e      # Re-enable exit on error
    trap error_exit ERR

    # Check if images directory exists
    if [ -d "images" ] && [ -f "images/logo.png" ]; then
        # Copying logo.png to .esim directory to access as icon
        cp -vp images/logo.png $config_dir
    else
        echo "Warning: Logo image not found. Icon may not display correctly."
    fi
}

####################################################################
#                   MAIN START FROM HERE                           #
####################################################################

### Checking if file is passed as argument to script

if [ "$#" -eq 1 ];then
    option=$1
else
    echo "USAGE : "
    echo "./install-eSim.sh --install"
    echo "./install-eSim.sh --uninstall"
    exit 1;
fi

## Checking flags

if [ $option == "--install" ];then

    set -e  # Set exit option immediately on error
    set -E  # inherit ERR trap by shell functions

    # Trap on function error_exit before exiting on error
    trap error_exit ERR

    echo "Enter proxy details if you are connected to internet through proxy"
    
    echo -n "Is your internet connection behind proxy? (y/n): "
    read getProxy
    if [ $getProxy == "y" -o $getProxy == "Y" ];then
        echo -n 'Proxy Hostname :'
        read proxyHostname

        echo -n 'Proxy Port :'
        read proxyPort

        echo -n username@$proxyHostname:$proxyPort :
        read username

        echo -n 'Password :'
        read -s passwd

        unset http_proxy
        unset https_proxy
        unset HTTP_PROXY
        unset HTTPS_PROXY
        unset ftp_proxy
        unset FTP_PROXY

        export http_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export https_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export https_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export HTTP_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort
        export HTTPS_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort
        export ftp_proxy=http://$username:$passwd@$proxyHostname:$proxyPort
        export FTP_PROXY=http://$username:$passwd@$proxyHostname:$proxyPort

        echo "Install with proxy"

    elif [ $getProxy == "n" -o $getProxy == "N" ];then
        echo "Install without proxy"
    
    else
        echo "Please select the right option"
        exit 0    
    fi

    # Calling functions
    createConfigFile
    installDependency
    installKicad
    copyKicadLibrary
    installNghdl
    installSky130Pdk
    createDesktopStartScript

    if [ $? -ne 0 ];then
        echo -e "\n\n\nERROR: Unable to install required packages. Please check your internet connection.\n\n"
        exit 0
    fi

    echo "-----------------eSim Installed Successfully-----------------"
    echo "Type \"esim\" in Terminal to launch it"
    echo "or double click on \"eSim\" icon placed on Desktop"

elif [ $option == "--uninstall" ];then
    echo -n "Are you sure? It will remove eSim completely including KiCad, Makerchip, NGHDL and SKY130 PDK along with their models and libraries (y/n):"
    read getConfirmation
    if [ $getConfirmation == "y" -o $getConfirmation == "Y" ];then
        echo "Removing eSim............................"
        sudo rm -rf $HOME/.esim $HOME/Desktop/esim.desktop /usr/bin/esim /usr/share/applications/esim.desktop
        echo "Removing KiCad..........................."
        sudo apt purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
        sudo rm -rf /usr/share/kicad
        
        # Check if KiCad apt repository file exists before attempting to remove
        if ls /etc/apt/sources.list.d/kicad* >/dev/null 2>&1; then
            sudo rm /etc/apt/sources.list.d/kicad*
        fi
        
        # Use the detected KiCad config directory for removal
        kicad_version=$(apt-cache policy kicad 2>/dev/null | grep -oP 'Installed: \K[0-9]+\.[0-9]+' || echo "6.0")
        kicad_major_version=${kicad_version%%.*}
        rm -rf $HOME/.config/kicad/$kicad_major_version.0

        echo "Removing Virtual env......................."
        if [ -d "$config_dir/env" ]; then
            sudo rm -r $config_dir/env
        fi

        echo "Removing SKY130 PDK......................"
        if [ -d "/usr/share/local/sky130_fd_pr" ]; then
            sudo rm -R /usr/share/local/sky130_fd_pr
        fi

        echo "Removing NGHDL..........................."
        if [ -d "library/modelParamXML/Nghdl" ]; then
            rm -rf library/modelParamXML/Nghdl/*
        fi
        if [ -d "library/modelParamXML/Ngveri" ]; then
            rm -rf library/modelParamXML/Ngveri/*
        fi
        
        if [ -d nghdl ]; then
            cd nghdl/
            if [ $? -eq 0 ]; then
                chmod +x install-nghdl.sh
                ./install-nghdl.sh --uninstall
                cd ../
                rm -rf nghdl
                if [ $? -eq 0 ]; then
                    echo -e "----------------eSim Uninstalled Successfully----------------"
                else
                    echo -e "\nError while removing some files/directories in \"nghdl\". Please remove it manually"
                fi
            else
                echo -e "\nCannot find \"nghdl\" directory. Please remove it manually"
            fi
        else
            echo "NGHDL directory not found. It may have been already removed."
            echo -e "----------------eSim Uninstalled Successfully----------------"
        fi
    elif [ $getConfirmation == "n" -o $getConfirmation == "N" ];then
        exit 0
    else 
        echo "Please select the right option."
        exit 0
    fi

else 
    echo "Please select the proper operation."
    echo "--install"
    echo "--uninstall"
fi
