#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################
########################################################################
#
# Description:
#    This script installs and runs Linux Test Project(LTP) on a guest VM
#
#    Steps:
#    1. Installs dependencies
#    2. Compiles and installs LTP
#    3. Runs LTP in lite mode
#    4. Collects results
#
#    No optional parameters are needed
#
########################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

# define regular stable releases in order to avoid unstable builds
# https://github.com/linux-test-project/ltp/tags
ltp_version="20180118"

TOP_BUILDDIR="/opt/ltp"
TOP_SRCDIR="$HOME/src"
LTP_RESULTS="/root/ltp-results.log"
LTP_OUTPUT="/root/ltp-output.log"
LTP_FAILED="/root/ltp-failed.log"
LTP_HTML="/root/ltp-results.html"
LTP_SKIPFILE="/root/ltp-skipfile"
DMESG_LOG_DIR="/root/ltp-kernel.log"

MAKE_JOBS=$(getconf _NPROCESSORS_ONLN)

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary() {
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState() {
    echo $1 > ~/state.txt
}

#######################################################################
# Installs SLES LTP dependencies
#######################################################################
InstallSLESDependencies() {
    zypper --non-interactive in m4
    zypper --non-interactive in libaio-devel
    zypper --non-interactive in libattr1
    zypper --non-interactive in libcap-progs
    zypper --non-interactive in 'bison>=2.4.1'
    zypper --non-interactive in db48-utils
    zypper --non-interactive in libdb-4_8
    zypper --non-interactive in perl-BerkeleyDB
    zypper --non-interactive in 'flex>=2.5.33'
    zypper --non-interactive in 'make>=3.81'
    zypper --non-interactive in 'automake>=1.10.2'
    zypper --non-interactive in 'autoconf>=2.61'
    zypper --non-interactive in gcc
    zypper --non-interactive in git-core

}

#######################################################################
# Installs UBUNTU LTP dependencies
#######################################################################
InstallUbuntuDependencies() {
    apt-get -y install autoconf
    apt-get -y install automake
    apt-get -y install m4
    apt-get -y install libaio-dev
    apt-get -y install libattr1
    apt-get -y install libcap-dev
    apt-get -y install bison
    apt-get -y install db48-utils
    apt-get -y install libdb4.8
    apt-get -y install libberkeleydb-perl
    apt-get -y install flex
    apt-get -y install make
    apt-get -y install gcc
    apt-get -y install git
    apt-get -y install expect
}

#######################################################################
# Installs RHEL LTP dependencies
#######################################################################
InstallRHELDependencies() {
    yum install -y autoconf
    yum install -y automake
    yum install -y m4
    yum install -y libaio-devel
    yum install -y libattr
    yum install -y libcap-devel
    yum install -y bison
    yum install -y db48-utils
    yum install -y libdb4.8
    yum install -y libberkeleydb-perl
    yum install -y flex
    yum install -y make
    yum install -y gcc
    yum install -y git
}

# Convert eol
dos2unix utils.sh

# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
   exit 1
fi

echo "Covers ${TC_COVERED}" > ~/summary.log

# Checks what Linux distro we are running on
GetDistro

LogMsg "Installing dependencies"
case $DISTRO in
    "suse"*)
        InstallSLESDependencies;;
    "ubuntu"* | "debian"*)
        InstallUbuntuDependencies;;
    "redhat"* | "centos"* | "fedora"*)
        InstallRHELDependencies;;
    *)
        LogMsg "Unknown Distro"
        UpdateTestState $ICA_TESTABORTED
        UpdateSummary "Unknown distro: $ICA_TESTABORTED"
        exit 1
        ;;
esac

test -d "$TOP_SRCDIR" || mkdir -p "$TOP_SRCDIR"
cd $TOP_SRCDIR

LogMsg "Cloning LTP"
git clone https://github.com/linux-test-project/ltp.git
TOP_SRCDIR="$HOME/src/ltp"

cd $TOP_SRCDIR
git checkout tags/$ltp_version

LogMsg "Configuring LTP..."
# use autoreconf to match the installed package versions
autoreconf -f
make autotools

test -d "$TOP_BUILDDIR" || mkdir -p "$TOP_BUILDDIR"
cd $TOP_BUILDDIR && "$TOP_SRCDIR/configure"
cd "$TOP_SRCDIR"
./configure

LogMsg "Compiling LTP..."
make all
if [ $? -gt 0 ]; then
    LogMsg "Error: Failed to compile LTP!"
    UpdateSummary "Error: Failed to compile LTP!"
    UpdateTestState $ICA_TESTFAILED
    exit 1
fi

LogMsg "Installing LTP..."
make install
if [ $? -gt 0 ]; then
        LogMsg "Error: Failed to install LTP!"
        UpdateSummary "Error: Failed to install LTP!"
        UpdateTestState $ICA_TESTFAILED
        exit 1
fi

cd $TOP_BUILDDIR

LogMsg "Running LTP..."
if [[ "${LTP_FULL}" == "true" ]];then
    ./runltp -c 4 -p -q -l $LTP_RESULTS -o $LTP_OUTPUT
else
    ./runltplite.sh -c 4 -p -q -l $LTP_RESULTS -o $LTP_OUTPUT
fi

grep -A 5 "Total Tests" $LTP_RESULTS >> ~/summary.log
if grep FAIL $LTP_OUTPUT ; then
    echo "Failed Tests:" >> ~/summary.log
    grep FAIL $LTP_OUTPUT | cut -d':' -f 2- >> ~/summary.log
fi

val=`cat summary.log | grep "Total Failures" | awk '{print $3}'`
comp_val="125"

if [[ "$val" -ge "$comp_val" ]];then
        UpdateTestState $ICA_TESTFAILED
        exit 1
else
        UpdateTestState $ICA_TESTCOMPLETED
        exit 0
fi