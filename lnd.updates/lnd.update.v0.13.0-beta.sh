#!/bin/bash

# LND Update Script
# Download:
# wget https://raw.githubusercontent.com/openoms/lightning-node-management/master/lnd.updates/lnd.update.v0.13.0.sh
# inspect
# cat lnd.update.v0.13.0.sh
# run
# bash lnd.update.v0.13.0.sh

lndVersion="0.13.0-beta"
downloadDir="$HOME/download/lnd"  # edit your download directory

PGPsigner="roasbeef"
PGPkeys="https://keybase.io/roasbeef/pgp_keys.asc"
PGPcheck="E4D85299674B2D31FAA1892E372CBD7633C61696"

#PGPsigner="bitconner"
#PGPkeys="https://keybase.io/$PGPsigner/pgp_keys.asc"
#PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"

#bitconner 
#PGPkeys="https://keybase.io/bitconner/pgp_keys.asc"
#PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"

#wpaulino
#PGPkeys="https://keybase.io/wpaulino/pgp_keys.asc"
#PGPcheck="729E9D9D92C75A5FBFEEE057B5DD717BEF7CA5B1"

echo "Detect CPU architecture ..."
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
if [ ${isARM} -eq 0 ] && [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ] ; then
  echo "!!! FAIL !!!"
  echo "Can only build on ARM, aarch64, x86_64 or i386 not on:"
  uname -m
  exit 1
else
  echo "OK running on $(uname -m) architecture."
fi

# get the lndSHA256 for the corresponding platform from manifest file
if [ ${isARM} -eq 1 ] ; then
  lndOSversion="armv7"
fi
if [ ${isAARCH64} -eq 1 ] ; then
  lndOSversion="arm64"
fi
if [ ${isX86_64} -eq 1 ] ; then
  lndOSversion="amd64"
fi
binaryName="lnd-linux-${lndOSversion}-v${lndVersion}.tar.gz"

rm -rf "${downloadDir}"
mkdir -p "${downloadDir}"
cd "${downloadDir}" || exit 1
# extract the SHA256 hash from the manifest file for the corresponding platform
wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-${PGPsigner}-v${lndVersion}.sig || exit 1

wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt || exit 1

# get the lndSHA256 for the corresponding platform from manifest file
lndSHA256=$(grep -i $binaryName manifest-v${lndVersion}.txt | cut -d " " -f1)

echo 
echo "*** LND v${lndVersion} for ${lndOSversion} ***"
echo "SHA256 hash: $lndSHA256"
echo 

# get LND binary
wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/${binaryName} || exit 1

# check binary was not manipulated (checksum test)
wget -O "${downloadDir}/pgp_keys.asc" ${PGPkeys}  || exit 1
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${lndSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded LND BINARY not matching SHA256 checksum: ${lndSHA256}"
  exit 1
fi

# check gpg finger print
gpg ./pgp_keys.asc
fingerprint=$(sudo gpg "${downloadDir}/pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD WARNING --> LND PGP author not as expected"
  echo "Should contain PGP: ${PGPcheck}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./pgp_keys.asc  || exit 1
sleep 3
verifyResult=$(gpg --verify manifest-${PGPsigner}-v${lndVersion}.sig manifest-v${lndVersion}.txt 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${GPGcheck}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
fi

if [ $(systemctl status lnd | grep -c active) -gt 0 ];then
  echo
  echo "# Stopping the lnd.service..."
  sudo systemctl stop lnd
fi
echo "# Install lnd-linux-${lndOSversion}-v${lndVersion}..." 
tar -xzf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-${lndOSversion}-v${lndVersion}/*
sleep 3
installed=$(lnd --version)
if [ ${#installed} -eq 0 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install LND"
  exit 1
fi
if [ -f /etc/systemd/system/lnd.service ];then
  echo "# Starting the lnd.service"
  sudo systemctl start lnd
  sleep 5
fi
echo
echo "# Installed ${installed}"

echo "# Check for the circuitbreaker.service"
if [ $(systemctl status circuitbreaker | grep -c active) -gt 0 ];then
  echo "# restart the circuitbreaker.service"
  sudo systemctl restart circuitbreaker
else
  echo "# circuitbreaker not running"
  echo "# Install with:"
  echo "'config.scripts/bonus.circuitbreaker.sh on'"
fi
echo
echo "# LND might take a couple of minutes to start."
echo
echo "# Monitor the lnd logs with:"
echo "'sudo tail -fn 30 /mnt/hdd/lnd/logs/bitcoin/mainnet/lnd.log'"
echo
echo "# unlock the LND wallet with:"
echo "'lncli unlock'"


