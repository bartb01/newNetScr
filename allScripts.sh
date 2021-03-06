#!/bin/bash

# Note: 'ZXCV' are comments for/by Bart, you can skip this.
# ZXCV change restrictions executeable e.g. chmod 755
# ZXCV see if possible to lose docker-compose-e2e.yaml --> docker-compose-cli can be removed instead? cli not for produciton?

#----------------------------------------------------[(1)Prerequisites]-------------------------------------------------------------

#Install prerequisites https://hyperledger-fabric.readthedocs.io/en/release-1.2/prereqs.html 

#-------------------------------------------[(2)Samples, binaries, docker images]---------------------------------------------------

# install curl linux
which curl
if [ "$?" -ne 0 ]; then
sudo apt-get install curl
fi

# ZXCV install node and npm, check versions
which node
if [ "$?" -ne 0 ]; then
curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
sudo apt-get install -y nodejs
fi

# install docker linux
which docker
if [ "$?" -ne 0 ]; then
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
apt-cache policy docker-ce
sudo apt-get install -y docker-ce
# ZXCV log out and log in again or reboot is required?
sudo usermod -a -G docker $USER
fi

# install docker-compose linux
which docker-compose
if [ "$?" -ne 0 ]; then
sudo curl -L "https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
fi

# Clone hyperledger/fabric-samples in current directory
# Checkout approriate version tag, 
# Install binaries config files for version specified in root of fabric-samples repo
# Download HLF docker images for specified version

# if fabric-samples directory exists, script has already been run. 
# ZXCV check for binaries, docker images and samples seperately 
# ZXCV only need fabric-samples/bin, skip the rest?
ls fabric-samples/
if [ "$?" -ne 0 ]; then
#ZXCV bash -s for parameter fabric version
curl -sSL http://bit.ly/2ysbOFE | bash -s 1.2.0 
fi
#ZXCV cURL -sSL:
#-s : silent mode
#-S : force show errors
#-L : location, follow redirects

# ZXCV skip these two lines:
# curl -sSL http://bit.ly/2ysbOFE | bash -s <fabric> <fabric-ca> <thirdparty>
# curl -sSL http://bit.ly/2ysbOFE | bash -s 1.2.0 1.2.0 0.4.10

# set to path environment variable (test if path is known with 'which cryptogen' to show the path to cryptogen)
# export PATH=$PATH:/home/   <PATH TO DOWNLOAD LOCATION>   /bin
which cryptogen
if [ "$?" -ne 0 ]; then
export PATH=$PATH:$(pwd)/fabric-samples/bin
fi

#---------------------------------------------------[(3)Add/change files]-----------------------------------------------------------

# required: if using cryptogen tool (fabric-ca is better), crypto-config.yaml is needed (containing network topology)
# required: docker-compose-e2e-template.yaml, which is used to create docker-compose-e2e.yaml, containing the right keys

#---------------------------------------------------[(4)Generate network]-----------------------------------------------------------

# ZXCV The cryptogen tool is not intended for a production environment because it generates all private keys in one location,
# which must then be copied to the appropriate host or container. (see https://github.com/hyperledger/fabric-samples/tree/release-1.2/fabric-ca
# or https://hyperledger-fabric-ca.readthedocs.io/en/latest/ or tutorials)


# We will use the cryptogen tool to generate the cryptographic material (x509 certs)
# for our various network entities.  The certificates are based on a standard PKI
# implementation where validation is achieved by reaching a common trust anchor.
#
# Cryptogen consumes a file - ``crypto-config.yaml`` - that contains the network
# topology and allows us to generate a library of certificates for both the
# Organizations and the components that belong to those Organizations.  Each
# Organization is provisioned a unique root certificate (``ca-cert``), that binds
# specific components (peers and orderers) to that Org.  Transactions and communications
# within Fabric are signed by an entity's private key (``keystore``), and then verified
# by means of a public key (``signcerts``).  You will notice a "count" variable within
# this file.  We use this to specify the number of peers per Organization; in our
# case it's two peers per Org.  The rest of this template is extremely
# self-explanatory.
#
# After we run the tool, the certs will be parked in a folder titled ``crypto-config``.

# Generates certificates using cryptogen tool
which cryptogen
if [ "$?" -ne 0 ]; then
echo "cryptogen tool not found. exiting"
exit 1
fi
#check for existing directory 'crypto-config' and remove it if its there. Then, create new folder with certs.
if [ -d "crypto-config" ]; then
rm -Rf crypto-config
fi
set -x
cryptogen generate --config=./crypto-config.yaml
res=$?
set +x
if [ $res -ne 0 ]; then
echo "Failed to generate certificates..."
exit 1
fi
echo

# //////////////////////////////////////////

# Using docker-compose-e2e-template.yaml, replace constants with private key file names
# generated by the cryptogen tool and output a docker-compose.yaml specific to this
# configuration

# sed on MacOSX does not support -i flag with a null extension. We will use
# 't' for our back-up's extension and delete it at the end of the function
ARCH=$(uname -s | grep Darwin)
if [ "$ARCH" == "Darwin" ]; then
OPTS="-it"
else
OPTS="-i"
fi

# Copy the template to the file that will be modified to add the private key
cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml

# The next steps will replace the template's contents with the
# actual values of the private key file names for the two CAs.
# ZXCV only automated for two orgs with specific name...
CURRENT_DIR=$PWD
cd crypto-config/peerOrganizations/org1.example.com/ca/
PRIV_KEY=$(ls *_sk)
cd "$CURRENT_DIR"
sed $OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
cd crypto-config/peerOrganizations/org2.example.com/ca/
PRIV_KEY=$(ls *_sk)
cd "$CURRENT_DIR"
sed $OPTS "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
# If MacOSX, remove the temporary backup of the docker-compose file
if [ "$ARCH" == "Darwin" ]; then
rm docker-compose-e2e.yamlt
fi

# //////////////////////////////////////////

# The `configtxgen tool is used to create four artifacts: orderer **bootstrap
# block**, fabric **channel configuration transaction**, and two **anchor
# peer transactions** - one for each Peer Org.
#
# The orderer block is the genesis block for the ordering service, and the
# channel transaction file is broadcast to the orderer at channel creation
# time.  The anchor peer transactions, as the name might suggest, specify each
# Org's anchor peer on this channel.
#
# Configtxgen consumes a file - ``configtx.yaml`` - that contains the definitions
# for the sample network. There are three members - one Orderer Org (``OrdererOrg``)
# and two Peer Orgs (``Org1`` & ``Org2``) each managing and maintaining two peer nodes.
# This file also specifies a consortium - ``SampleConsortium`` - consisting of our
# two Peer Orgs.  Pay specific attention to the "Profiles" section at the top of
# this file.  You will notice that we have two unique headers. One for the orderer genesis
# block - ``TwoOrgsOrdererGenesis`` - and one for our channel - ``TwoOrgsChannel``.
# These headers are important, as we will pass them in as arguments when we create
# our artifacts.  This file also contains two additional specifications that are worth
# noting.  Firstly, we specify the anchor peers for each Peer Org
# (``peer0.org1.example.com`` & ``peer0.org2.example.com``).  Secondly, we point to
# the location of the MSP directory for each member, in turn allowing us to store the
# root certificates for each Org in the orderer genesis block.  This is a critical
# concept. Now any network entity communicating with the ordering service can have
# its digital signature verified.
#
# This function will generate the crypto material and our four configuration
# artifacts, and subsequently output these files into the ``channel-artifacts``
# folder.
#
# If you receive the following warning, it can be safely ignored:
#
# [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
#
# You can ignore the logs regarding intermediate certs, we are not using them in
# this crypto implementation.

# Generate orderer genesis block, channel configuration transaction and
# anchor peer update transactions
which configtxgen
if [ "$?" -ne 0 ]; then
echo "configtxgen tool not found. exiting"
exit 1
fi

#set channel name
CHANNEL_NAME=mychannel
mkdir -p ./channel-artifacts

echo "##########################################################"
echo "#########  Generating Orderer Genesis block ##############"
echo "##########################################################"
# Note: For some unknown reason (at least for now) the block file can't be
# named orderer.genesis.block or the orderer will fail to launch!
set -x
configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block
res=$?
set +x
if [ $res -ne 0 ]; then
echo "Failed to generate orderer genesis block..."
exit 1
fi
echo
echo "#################################################################"
echo "### Generating channel configuration transaction 'channel.tx' ###"
echo "#################################################################"
set -x
configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
res=$?
set +x
if [ $res -ne 0 ]; then
echo "Failed to generate channel configuration transaction..."
exit 1
fi

echo
echo "#################################################################"
echo "#######    Generating anchor peer update for Org1MSP   ##########"
echo "#################################################################"
set -x
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
res=$?
set +x
if [ $res -ne 0 ]; then
echo "Failed to generate anchor peer update for Org1MSP..."
exit 1
fi

echo
echo "#################################################################"
echo "#######    Generating anchor peer update for Org2MSP   ##########"
echo "#################################################################"
set -x
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate \
./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
res=$?
set +x
if [ $res -ne 0 ]; then
echo "Failed to generate anchor peer update for Org2MSP..."
exit 1
fi
echo "all has been generated"

#--------------------------------------------------[(5)Check prerequisites]---------------------------------------------------------

# Versions of fabric known not to work with this release of first-network
BLACKLISTED_VERSIONS="^1\.0\. ^1\.1\.0-preview ^1\.1\.0-alpha"

# Do some basic sanity checking to make sure that the appropriate versions of fabric
# binaries/images are available.

# Note, we check configtxlator externally because it does not require a config file, and peer in the
# docker image because of FAB-8551 that makes configtxlator return 'development version' in docker
IMAGETAG=latest
LOCAL_VERSION=$(configtxlator version | sed -ne 's/ Version: //p')
DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGETAG peer version | sed -ne 's/ Version: //p' | head -1)

echo "LOCAL_VERSION=$LOCAL_VERSION"
echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
echo "=================== WARNING ==================="
echo "  Local fabric binaries and docker images are  "
echo "  out of  sync. This may cause problems.       "
echo "==============================================="
fi

for UNSUPPORTED_VERSION in $BLACKLISTED_VERSIONS; do
echo "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
if [ $? -eq 0 ]; then
    echo "ERROR! Local Fabric binary version of $LOCAL_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-samples."
    exit 1
fi

echo "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
if [ $? -eq 0 ]; then
    echo "ERROR! Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-samples."
    exit 1
fi
done

#-----------------------------------------------------[(6)Start network]------------------------------------------------------------

# Generate the needed certificates, the genesis block and start the network.
# ZXCV database standard goleveldb, can switch to couchdb
IF_COUCHDB=goleveldb
COMPOSE_FILE=docker-compose-cli.yaml

if [ "${IF_COUCHDB}" == "couchdb" ]; then
IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE -f docker-compose-couch.yaml up -d 2>&1
else
IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE up -d 2>&1
fi
if [ $? -ne 0 ]; then
echo "ERROR !!!! Unable to start network"
exit 1
fi

# default delay between commands
CLI_DELAY=3
# language can be either node or golang
LANGUAGE=node
# 
CLI_TIMEOUT=10
# verbose mode (for debugging)
VERBOSE=false
# now run the end to end script
# ZXCV change path scripts/script.sh 
docker exec cli scripts/script.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE
if [ $? -ne 0 ]; then
echo "ERROR !!!! Test failed"
exit 1
fi

#-----------------------------------------------------[(7)Stop network]-------------------------------------------------------------

# run ./stop.sh
