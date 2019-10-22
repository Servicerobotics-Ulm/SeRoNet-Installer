#!/bin/bash

# This script calls itself recursively depending on the selected options.
# The script can also be deliberately called with additional arguments to
# trigger individual instalaltion steps. The arguments are as follows:

#./SriptName <instalation-step-name> <installation-root-folder> <log-file>

# If you don't provide any of these arguments, then the script will open a GUI where you
# can select the instalaltion steps that you would like to execute.

################################
# Insert code after here
################################
COMMIT='$Id$'

source ~/.profile

SCRIPT_DIR=`pwd`
SCRIPT_NAME=$0

SCRIPT_COMMAND="menu"
if [ $# -gt 0 ]; then
    SCRIPT_COMMAND=$1
fi

INSTALLATION_DIR="$HOME/SOFTWARE"
if [ $# -gt 1 ]; then
    INSTALLATION_DIR=$2
fi

LOGFILE=`basename $0`.`date +"%Y%m%d%H%M"`.log
if [ $# -gt 2 ]; then
  LOGFILE=$3
fi

CURRENT_ACTION_NUMBER=$((0))
if [ $# -gt 3 ]; then
    CURRENT_ACTION_NUMBER=$4
fi

SELECTED_ACTIONS_COUNTER=$((0))
if [ $# -gt 4 ]; then
    SELECTED_ACTIONS_COUNTER=$5
fi

# these variables define the used package versions/names
TOOLING_VERSION="1.0"
TOOLING_URL="https://web2.servicerobotik-ulm.de/files/SeRoNet_Tooling/$TOOLING_VERSION/SeRoNet-Tooling-v$TOOLING_VERSION.tar.gz"
TOOLING_LAUNCHER="SeRoNet-Tooling.desktop"
OPEN62541_VERSION="v1.0"
OPEN62541_CPP_WRAPPER_VERSION="v1.0"

function abort() {
	echo 100 >> /tmp/install-msg.log
	echo -e "\n\n### Aborted.\nYou can find the logfile $LOGFILE in your current working directory:\n"
	pwd
	kill $$
}

function askabort() {
	if zenity --width=400 --question --text="An error occurred (see log file). Abort update script?\n"; then
		abort
		exit 1
	fi
}

function open_progress_window() {
	# start progress GUI with 10% progress
	echo "10" > /tmp/install-msg.log
	# open progress GUI window and monitor progress using the /tmp/install-msg.log file
	tail -f /tmp/install-msg.log | zenity --progress --title="Installing preselected packages" --auto-close --text="Starting Installation..." --width=400 --percentage=0 || askabort &
}

# this function shows the text from the first argument $1 in the progress window
function progressbarinfo() {
	echo "# $1" >> /tmp/install-msg.log
	echo "-- $1"
	echo -e "\n"
}

# this function takes the percentage number from the first argument $1 (expected 0-100) and proportionally advances the progress bar within the sub-range of the currenly executed action-step
function subprogress() {
	awk "BEGIN { print $CURRENT_ACTION_NUMBER/$SELECTED_ACTIONS_COUNTER*100+$1/$SELECTED_ACTIONS_COUNTER}" >> /tmp/install-msg.log
}

function start_logging() {
	exec > >(tee $LOGFILE);
	echo '### Update script start (git=$COMMIT)'; 
	date; 
	echo "Logfile: $LOGFILE";
	echo $! > /tmp/smartsoft-install-update.pid
}

# check if sudo is allowed and if necessary ask for password
function check_sudo() {
  local prompt

  # check for sudo rights without prompt
  prompt=$(sudo -nv 2>&1)
  if [ $? -eq 0 ]; then
    echo "has_sudo"
  elif echo $prompt | grep -q '^sudo:'; then
    PASSWD=$(zenity --title "sudo password" --password) || exit 1
    echo -e "$PASSWD\n" | sudo -Sv
    if [ $? -eq 0 ]; then
      echo "has_sudo"
    else
      abort
    fi
  else
    abort
  fi
}

function update_open62541_installation() {
	progressbarinfo "Cloning the open62541 Github repository..."

	if [ -d $INSTALLATION_DIR/open62541 ]; then
		cd $INSTALLATION_DIR/open62541
		git reset --hard HEAD
		git fetch --tags || askabort
	else
		cd $INSTALLATION_DIR
		git clone https://github.com/open62541/open62541.git
		cd open62541
		git fetch --tags || askabort
	fi

	progressbarinfo "Building and installing the open62541 library..."
	cd $INSTALLATION_DIR/open62541
	git checkout $OPEN62541_VERSION
	git submodule init
	git submodule update
	mkdir -p build
	cd build
	cmake -DUA_BUILD_EXAMPLES=ON -DUA_ENABLE_DISCOVERY_MULTICAST=ON -DBUILD_SHARED_LIBS=ON ..
	make
	check_sudo
	sudo make install
}

function update_smartsoft_api_installation() {
	progressbarinfo "Cloning the SmartSoftComponentDeveloperAPIcpp Github repository ..."
	if [ -d $INSTALLATION_DIR/smartsoft-ace-mdsd-v3/repos/SmartSoftComponentDeveloperAPIcpp ]; then
		cd $INSTALLATION_DIR/smartsoft-ace-mdsd-v3/repos/SmartSoftComponentDeveloperAPIcpp
		git reset --hard HEAD
		git pull || askabort
	else
		mkdir -p $INSTALLATION_DIR/smartsoft-ace-mdsd-v3/repos
		cd $INSTALLATION_DIR/smartsoft-ace-mdsd-v3/repos
		git clone https://github.com/Servicerobotics-Ulm/SmartSoftComponentDeveloperAPIcpp.git || askabort
		cd SmartSoftComponentDeveloperAPIcpp
	fi

	# make sure the SMART_ROOT_ACE variable is set correctly
	export SMART_ROOT_ACE=$INSTALLATION_DIR/smartsoft

	progressbarinfo "Installing the SmartSoftComponentDeveloperAPIcpp library ..."
	mkdir -p build
	cd build || askabort
	cmake .. || askabort
	make install || askabort
}

if `grep --ignore-case xenial /etc/os-release > /dev/null`; then 
	UBUNTU_16=true
	GCC_COMPILER="g++"
fi

if `grep --ignore-case bionic /etc/os-release > /dev/null`; then 
	UBUNTU_18=true
	GCC_COMPILER="g++-7"
fi

if ! [ -x "$(command -v zenity)" ]; then
	echo
	echo "ERROR: zenity not found. Install using 'sudo apt-get install zenity'"
	echo
	exit
fi


case "$SCRIPT_COMMAND" in

###############################################################################
# MENU (default entry point)
###############################################################################
menu)
	ACTIONS=$(zenity \
		--title "SeRoNet Infrastructure Installer v1.0" \
		--text "This is the automatic installation script for the SeRoNet Tooling and the related development infrastructure.\nPlease select the packages to be installed." \
		--list --checklist \
		--height=350 \
		--width=430 \
		--column="" --column="Action" --column="Description" \
		--hide-column=2 --print-column=2 --hide-header \
		--separator=" " \
		true tooling "SeRoNet Tooling Collection (recommended)" \
		true ace-smartsoft "ACE/SmartSoft Kernel (recommended)" \
		true opcua-backend "SeRoNet OPC UA Backend (recommended)" \
		false opcua-devices "OPC UA Device Repository (optional)" \
		false ros "ROS base installation (optional)" \
	) || exit 1

	INSTALLATION_DIR=$(zenity --title "SeRoNet Infrastructure Installer v1.0" \
		--entry --text="Provide the root installation folder where the git repositories should be cloned into." \
		--entry-text="$HOME/SOFTWARE" \
	) || exit 1

	start_logging

	echo "create installation folder $INSTALLATION_DIR (if it doesn't exist yet)"
	mkdir -p $INSTALLATION_DIR

	# first we will count the number of selected actions 
	# (this will be used to calculate
	for CURR_ACTION in $ACTIONS; do
	  SELECTED_ACTIONS_COUNTER=$(($SELECTED_ACTIONS_COUNTER + 1))
	done

	open_progress_window

	CURRENT_ACTION_NUMBER=$((0))
	for CURR_ACTION in $ACTIONS; do
	    # execute the next action
	    echo "#### Execute installation step $CURR_ACTION ####"
	    bash $SCRIPT_NAME $CURR_ACTION $INSTALLATION_DIR $LOGFILE $CURRENT_ACTION_NUMBER $SELECTED_ACTIONS_COUNTER
	    # abort executing further commands if the previos command returned with != 0
	    if [ $? -ne 0 ]; then
	      exit $?
	    fi
	    # calculate the progress percentage number and print it to the /tmp/install-msg.log, so zenity gets updated
	    CURRENT_ACTION_NUMBER=$(($CURRENT_ACTION_NUMBER + 1))
	    awk "BEGIN { print $CURRENT_ACTION_NUMBER/$SELECTED_ACTIONS_COUNTER*100 }" >> /tmp/install-msg.log
	done
	
	zenity --info --width=400 --text="Installation Finished! Some environment settings in .profile have been updated. In order to use them, do one of the following steps:\n\n- Restart your computer\n- Logout/Login again, or\n- Execute 'source ~/.profile'"

	# xdg-open http://robot.one
;;

###############################################################################
tooling)
	# check if OpenJDK 8 is installed
	if [[ $(java -version 2>&1) == "openjdk version \"1.8"* ]]; then
		echo "-- found OpenJDK 1.8"
	else
		progressbarinfo "Installing dependency OpenJDK 8 ..."
		check_sudo
		sudo apt install -y openjdk-8-jre || askabort
	fi

	cd $INSTALLATION_DIR
	progressbarinfo "Downloading SeRoNet Tooling from: $TOOLING_URL"
	wget -N $TOOLING_URL || askabort
	subprogress 50
	progressbarinfo "Extracting SeRoNet Tooling archive SeRoNet-Tooling-v$TOOLING_VERSION.tar.gz" 
	tar -xzf SeRoNet-Tooling-v$TOOLING_VERSION.tar.gz || askabort

	# create a desktop launcher
	echo "#!/usr/bin/xdg-open" > $INSTALLATION_DIR/$TOOLING_LAUNCHER
	echo "[Desktop Entry]" >> $INSTALLATION_DIR/$TOOLING_LAUNCHER
	echo "Name=SeRoNet Tooling Collection v$TOOLING_VERSION" >> $INSTALLATION_DIR/$TOOLING_LAUNCHER	
	echo "Version=$TOOLING_VERSION" >> $INSTALLATION_DIR/$TOOLING_LAUNCHER
	
	cd SeRoNet-Tooling-v$TOOLING_VERSION
	echo "Exec=$PWD/eclipse" >> $INSTALLATION_DIR/$TOOLING_LAUNCHER

	cd plugins/de.seronet_projekt.branding*
	cd images
	echo "Icon=$PWD/logo64.png" >> $INSTALLATION_DIR/$TOOLING_LAUNCHER

	echo "Terminal=false" >> $INSTALLATION_DIR/$TOOLING_LAUNCHER
	echo "Type=Application" >> $INSTALLATION_DIR/$TOOLING_LAUNCHER
	echo "Categories=Development;" >> $INSTALLATION_DIR/$TOOLING_LAUNCHER

	cd $INSTALLATION_DIR
	chmod +x $TOOLING_LAUNCHER
	mv $TOOLING_LAUNCHER $HOME/.local/share/applications/
	cp $HOME/.local/share/applications/$TOOLING_LAUNCHER $HOME/Desktop/
	gio set $HOME/Desktop/$TOOLING_LAUNCHER "metadata::trusted" yes
;;

###############################################################################
ace-smartsoft)

	check_sudo
	progressbarinfo "Installing generic dependencies, like cmake, gcc, ssh, doxygen, etc..."

	if [ "$UBUNTU_16" = true ]; then
		sudo apt-get -y --force-yes install $GCC_COMPILER ssh-askpass git flex bison htop tree cmake cmake-curses-gui subversion sbcl doxygen \
		 meld expect wmctrl libopencv-dev libboost-all-dev libftdi-dev libcv-dev libcvaux-dev libhighgui-dev \
		 build-essential pkg-config freeglut3-dev zlib1g-dev zlibc libusb-1.0-0-dev libdc1394-22-dev libavformat-dev libswscale-dev \
		 lib3ds-dev libjpeg-dev libgtest-dev libeigen3-dev libglew-dev vim vim-gnome libxml2-dev libxml++2.6-dev libmrpt-dev ssh sshfs xterm libjansson-dev || askabort
	elif [ "$UBUNTU_18" = true ]; then
		sudo apt -y --force-yes install $GCC_COMPILER ssh-askpass git flex bison htop tree cmake cmake-curses-gui subversion sbcl doxygen \
		 meld expect wmctrl libopencv-dev libboost-all-dev libftdi-dev \
		 build-essential pkg-config freeglut3-dev zlib1g-dev zlibc libusb-1.0-0-dev libdc1394-22-dev libavformat-dev libswscale-dev \
		 lib3ds-dev libjpeg-dev libgtest-dev libeigen3-dev libglew-dev vim vim-gnome libxml2-dev libxml++2.6-dev libmrpt-dev ssh sshfs xterm libjansson-dev || askabort
	fi

	subprogress "20"

	if [ "$UBUNTU_16" = true ]; then
		if [ -f "/opt/ACE_wrappers/lib/libACE.so" ]; then
			echo "-- found /opt/ACE_wrappers/"
		else
			progressbarinfo "Downloading and building the ACE library ..."
			wget -nv https://github.com/Servicerobotics-Ulm/AceSmartSoftFramework/raw/master/INSTALL-ACE-6.0.2.sh -O /tmp/INSTALL-ACE-6.0.2.sh || askabort
			chmod +x /tmp/INSTALL-ACE-6.0.2.sh || askabort
			check_sudo
			sudo /tmp/INSTALL-ACE-6.0.2.sh /opt || askabort
			sudo sh -c 'echo "/opt/ACE_wrappers/lib" > /etc/ld.so.conf.d/ace.conf'
			sudo ldconfig || askabort
		fi

	elif [ "$UBUNTU_18" = true ]; then
		if [ -f "/usr/lib/libACE.so" ]; then
			echo "-- found /usr/lib/libACE.so"
		else
			check_sudo
			progressbarinfo "Installing dependency libace-dev"
			sudo apt install -y libace-dev || askabort
		fi
	fi

	subprogress "30"

	mkdir -p $INSTALLATION_DIR/smartsoft-ace-mdsd-v3/repos || askabort
	ln -s $INSTALLATION_DIR/smartsoft-ace-mdsd-v3 $INSTALLATION_DIR/smartsoft

	if [ "$UBUNTU_16" = true ]; then
		if ! grep -q "ACE_ROOT" "$HOME/.profile"; then
			echo "export ACE_ROOT=/opt/ACE_wrappers" >> $HOME/.profile
		fi
	fi
	if ! grep -q "SMART_ROOT_ACE" "$HOME/.profile"; then
		echo "export SMART_ROOT_ACE=$INSTALLATION_DIR/smartsoft" >> $HOME/.profile
		echo "export SMART_PACKAGE_PATH=\$SMART_ROOT_ACE/repos" >> $HOME/.profile
	fi
	if ! grep -q "SMART_ROOT_ACE" "$HOME/.bashrc"; then
		echo "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$SMART_ROOT_ACE/lib" >> $HOME/.bashrc
	fi

	source ~/.profile 
	
	update_smartsoft_api_installation
	
	subprogress "40"

	progressbarinfo "Cloning the AceSmartSoftFramework Github repositry ..."
	cd $INSTALLATION_DIR/smartsoft-ace-mdsd-v3/repos || askabort
	if [ -d AceSmartSoftFramework ]; then
		cd AceSmartSoftFramework
		git reset --hard HEAD
		git pull || askabort
	else
		git clone https://github.com/Servicerobotics-Ulm/AceSmartSoftFramework.git || askabort
		cd AceSmartSoftFramework
	fi

	subprogress "70"

	progressbarinfo "Building the ACE/SmartSoft Kernel ..."
	mkdir -p build
	cd build || askabort
	cmake ..
	make install || askabort

;;

###############################################################################
opcua-backend)

	progressbarinfo "Installing OPC UA Backend..."

	check_sudo
	sudo apt-get -y --force-yes install $GCC_COMPILER git cmake || askabort

	subprogress "10"

	update_open62541_installation

	subprogress "30"

	progressbarinfo "Cloning the Open62541Cpp Github repository ..."
	if [ -d $INSTALLATION_DIR/open62541Cpp ]; then
		cd $INSTALLATION_DIR/open62541Cpp
		git reset --hard HEAD
		git pull origin master
	else
		cd $INSTALLATION_DIR
		git clone https://github.com/seronet-project/open62541Cpp.git || askabort
	fi
	
	subprogress "40"
	progressbarinfo "Building and installing the Open62541Cpp library ..."

	cd $INSTALLATION_DIR/open62541Cpp
	mkdir -p build
	cd build
	cmake -DBUILD_SHARED_LIBS=ON .. || askabort
	make || askabort
	check_sudo
	sudo make install || askabort

	subprogress "50"
	update_smartsoft_api_installation
	subprogress "60"

	progressbarinfo "Cloning the SeRoNet-OPC-UA-Backend Github repository ..."
	if [ -d $INSTALLATION_DIR/SeRoNet-OPC-UA-Backend ]; then
		cd $INSTALLATION_DIR/SeRoNet-OPC-UA-Backend
		git reset --hard HEAD
		git pull origin master
	else
		cd $INSTALLATION_DIR
		git clone https://github.com/seronet-project/SeRoNet-OPC-UA-Backend.git || askabort
	fi

	subprogress "70"
		
	progressbarinfo "Building and installing the SeRoNet-OPC-UA-Backend library ..."
	cd $INSTALLATION_DIR/SeRoNet-OPC-UA-Backend
	mkdir -p build
	cd build
	cmake -DBUILD_SHARED_LIBS=ON -DSmartSoft_CD_API_DIR=$SMART_ROOT_ACE/modules .. || askabort
	make || askabort
	check_sudo
	sudo make install || askabort
;;

###############################################################################
opcua-devices)

	progressbarinfo "Installing OPC UA Device Repository ..."

	check_sudo
	sudo apt-get -y --force-yes install $GCC_COMPILER git cmake build-essential pkg-config python python-six

	subprogress "10"

	update_open62541_installation

	subprogress "30"

	progressbarinfo "Cloning the Open62541CppWrapper Github repository ..."
	if [ -d $INSTALLATION_DIR/Open62541CppWrapper ]; then
		cd Open62541CppWrapper
		git reset --hard HEAD
	else
		cd $INSTALLATION_DIR
		git clone https://github.com/Servicerobotics-Ulm/Open62541CppWrapper.git || askabort
	fi

	subprogress "40"
	progressbarinfo "Building and installing the Open62541CppWrapper library ..."

	cd $INSTALLATION_DIR/Open62541CppWrapper
	git checkout $OPEN62541_CPP_WRAPPER_VERSION || askabort
	mkdir -p build
	cd build
	cmake .. || askabort
	make || askabort
	check_sudo
	sudo make install || askabort

	subprogress "60"

	progressbarinfo "Cloning the OpcUaDeviceRepository Github repository ..."
	if [ -d $INSTALLATION_DIR/OpcUaDeviceRepository ]; then
		cd OpcUaDeviceRepository
		git reset --hard HEAD
	else
		cd $INSTALLATION_DIR
		git clone https://github.com/Servicerobotics-Ulm/OpcUaDeviceRepository.git || askabort
	fi

	subprogress "70"
	progressbarinfo "Building and installing the OpcUaDeviceRepository library ..."

	cd $INSTALLATION_DIR/OpcUaDeviceRepository
	mkdir -p build
	cd build
	cmake .. || askabort
	make || askabort
	#check_sudo
	#sudo make install
;;

###############################################################################
ros)

	if [ -d "/opt/ros" ]; then
		zenity --info --width=400 --text="An existing ROS installation found at /opt/ros; skip installing new ROS!"  --height=100
	else
		if [ "$UBUNTU_16" = true ]; then
            ROS_DISTRO="kinetic"
		elif [ "$UBUNTU_18" = true ]; then
            ROS_DISTRO="melodic"
        fi
			progressbarinfo "Installing ROS $ROS_DISTRO..."
			check_sudo
			sudo sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'
			sudo apt-key adv --keyserver 'hkp://keyserver.ubuntu.com:80' --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654
			sudo apt-get update
			subprogress "20"
			sudo apt-get install -y ros-$ROS_DISTRO-desktop
			echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> ~/.bashrc
			subprogress "80"
			source ~/.bashrc
			sudo rosdep init
			rosdep update
	fi
;;

esac
