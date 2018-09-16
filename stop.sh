# ZXCV to stop docker containers, run following, but also clear them and remove unwanted images, check other scripts!
# ZXCV below 'latest' should be $IMAGE_TAG

# to stop containers
docker-compose -f docker-compose-cli.yaml down --volumes --remove-orphans

# Bring down the network, deleting the volumes
# Delete any ledger backups
docker run -v $PWD:/tmp/first-network --rm hyperledger/fabric-tools:latest rm -Rf /tmp/first-network/ledgers-backup

# clear containers
CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /dev-peer.*.mycc.*/) {print $1}')
if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
echo "---- No containers available for deletion ----"
else
docker rm -f $CONTAINER_IDS
fi  

# cleanup images
DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*.mycc.*/) {print $3}')
if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
echo "---- No images available for deletion ----"
else
docker rmi -f $DOCKER_IMAGE_IDS
fi

# remove orderer block and other channel configuration transactions and certs
rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config ./org3-artifacts/crypto-config/ channel-artifacts/org3.json
# remove the docker-compose yaml file that was customized to the example
rm -f docker-compose-e2e.yaml
