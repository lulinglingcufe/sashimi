#!/bin/bash

# Copyright Tecnalia Research & Innovation (https://www.tecnalia.com)
# Copyright Tecnalia Blockchain LAB
#
# SPDX-License-Identifier: Apache-2.0

#BASH CONFIGURATION
# Enable colored log
export TERM=xterm-256color

function banner(){

echo "                                __                   __ ";
echo "   __  __ __  __ ____   ____   / /_   ____ _ ____   / /_";
echo "  / / / // / / // __ \ / __ \ / __ \ / __ \`// __ \ / __/";
echo " / /_/ // /_/ // / / // /_/ // / / // /_/ // / / // /_  ";
echo " \__, / \__,_//_/ /_// .___//_/ /_/ \__,_//_/ /_/ \__/  ";
echo "/____/              /_/                                 ";

}

# HELPER FUNCTIONS
# Check whether a given container (filtered by name) exists or not
function existsContainer(){
	containerName=$1
	if [ -n "$(docker ps -aq -f name=$containerName)" ]; then
	    return 0 #true
	else
		return 1 #false
	fi
}

# HELPER FUNCTIONS
# Check whether a given network (filtered by name) exists or not
function existsNetwork(){
	networkName=$1
	if [ -n "$(docker network ls -q -f name=$networkName)" ]; then
	    return 0 #true
	else
		return 1 #false
	fi
}

# Check whether a given network (filtered by name) exists or not
function existsImage(){
	imageName=$1
	if [ -n "$(docker images -a -q $imageName)" ]; then
	    return 0 #true
	else
		return 1 #false
	fi
}

# Configure settings of Sashimi
function config(){
	# BEGIN: GLOBAL VARIABLES OF THE SCRIPT
	defaultNetworkName="net1"
	if [ -z "$1" ]; then
		echo "No custom Hyperledger Network configuration supplied. Using default network name: $defaultNetworkName"
		yunphantBlockchainNetworkName=$defaultNetworkName
	else
		yunphantBlockchainNetworkName=$1
		echo "Using custom Hyperledger Network configuration. Network name: $yunphantBlockchainNetworkName"
	fi
	docker_network_name="sashimi-net"
	# Default Hyperledger Explorer Database Credentials.
	explorer_db_user="yunphant"
	explorer_db_pwd="yunphant"
	explorer_db_name="sashimidb"
	#configure explorer to connect to specific Blockchain network using given configuration
	network_config_file=$(pwd)/examples/$yunphantBlockchainNetworkName/config.json
	#configure explorer to connect to specific Blockchain network using given crypto materials
	network_crypto_lib=$(pwd)/examples/$yunphantBlockchainNetworkName/libsmcryptokit.so
	network_crypto_base_path=$(pwd)/examples/$yunphantBlockchainNetworkName/crypto
	#configure swagger file if you want to use rest api swagger
	network_swagger_file=$(pwd)/examples/$yunphantBlockchainNetworkName/swagger.json
	# local vnet configuration

	# Docker network configuration
	# Address:   192.168.10.0         11000000.10101000.00001010. 00000000
	# Netmask:   255.255.255.0 = 24   11111111.11111111.11111111. 00000000
	# Wildcard:  0.0.0.255            00000000.00000000.00000000. 11111111
	# =>
	# Network:   192.168.10.0/24      11000000.10101000.00001010. 00000000
	# HostMin:   192.168.10.1         11000000.10101000.00001010. 00000001
	# HostMax:   192.168.10.254       11000000.10101000.00001010. 11111110
	# Broadcast: 192.168.10.255       11000000.10101000.00001010. 11111111
	# Hosts/Net: 254                   Class C, Private Internet
	subnet=192.168.10.0/24

	# database container configuration
	sashimi_db_tag="sashimidb"
	sashimi_db_name="sashimidb"
	db_ip=192.168.10.11

	# sashimi container configuration
	sashimi_tag="sashimi"
	sashimi_name="sashimi"
	explorer_ip=192.168.10.12
	# END: GLOBAL VARIABLES OF THE SCRIPT
}

function deploy_prepare_network(){
	if existsNetwork $docker_network_name; then
		echo "Removing old configured docker vnet for Sashimi"
		# to avoid active endpoints
		stop_database
		stop_explorer
		docker network rm $docker_network_name
	fi

	echo "Creating default Docker vnet for Sashimi"
	docker network create --subnet=$subnet $docker_network_name
}

function deploy_build_database(){
	echo "Building Sashimi Database image from current local version..."
	docker build -f postgres-Dockerfile --tag $sashimi_db_tag .
}

function stop_database(){
	if existsContainer $sashimi_db_name; then
		echo "Stopping previously deployed Sashimi DATABASE instance..."
		docker stop $sashimi_db_name && \
		docker rm $sashimi_db_name
	fi
}

function deploy_run_database(){
	stop_database

	# deploy database with given user/password configuration
	# By default, since docker is used, there are no users created so default available user is
	# postgres/password
	echo "Deploying Database (POSTGRES) container at $db_ip"
	docker run \
		-d \
		--name $sashimi_db_name \
		--net $docker_network_name --ip $db_ip \
        -e DATABASE_DATABASE=$explorer_db_name \
        -e DATABASE_USERNAME=$explorer_db_user \
        -e DATABASE_PASSWORD=$explorer_db_pwd  \
		$sashimi_db_tag
}

function deploy_load_database(){
	echo "Preparing database for Sashimi"
	echo "Waiting...6s"
	sleep 1s
	echo "Waiting...5s"
	sleep 1s
	echo "Waiting...4s"
	sleep 1s
	echo "Waiting...3s"
	sleep 1s
	echo "Waiting...2s"
	sleep 1s
	echo "Waiting...1s"
	sleep 1s
	echo "Creating default database schemas..."
	docker exec $sashimi_db_name /bin/bash /opt/createdb.sh
}

function deploy_build_explorer(){
	echo "Building Sashimi image from current local version..."
	docker build --tag $sashimi_tag .
	echo "Sashimi network configuration file is located at $network_config_file"
	echo "Sashimi network crypto material at $network_crypto_base_path"
}

function stop_explorer(){
	if existsContainer $sashimi_name; then
		echo "Stopping previously deployed Sashimi instance..."
		docker stop $sashimi_name && \
		docker rm $sashimi_name
	fi
}

function deploy_run_explorer(){
	stop_explorer

	echo "Deploying Sashimi container at $explorer_ip"
	docker run \
		-d \
		--restart="always" \
		--name $sashimi_name \
		--net $docker_network_name --ip $explorer_ip \
		-e DATABASE_HOST=$db_ip \
		-e DATABASE_DATABASE=$explorer_db_name \
		-e DATABASE_USERNAME=$explorer_db_user \
		-e DATABASE_PASSWD=$explorer_db_pwd \
		-v $network_config_file:/opt/explorer/app/platform/fabric/config.json \
		-v $network_swagger_file:/opt/explorer/swagger.json \
		-v $network_crypto_base_path:/tmp/crypto \
		-v $network_crypto_lib:/tmp/libsmcryptokit.so \
		-p 8890:8080 \
		$sashimi_tag
}

function connect_to_network(){
    echo "Trying to join to existing network $1"
    docker network connect $1 $(docker ps -qf name=^/$sashimi_name$)
    docker network connect $1 $(docker ps -qf name=^/$sashimi_db_name$)
}

function deploy(){

	deploy_prepare_network

	deploy_run_database
	deploy_load_database

	deploy_run_explorer

    if [ -n "$2" ]; then
        connect_to_network $2
    fi
}

function main(){
	banner
    #Pass arguments to function exactly as-is
    config "$@"

	MODE=$1;
    if [ "$MODE" == "--down" ]; then
	    echo "Stopping Sashimi containers..."
    elif [ "$MODE" == "--clean" ]; then
	    echo "Cleaning Sashimi images..."
        stop_explorer
        stop_database
        docker rmi $(docker images -q ${sashimi_db_tag})
        docker rmi $(docker images -q ${sashimi_tag})
    elif [ "$MODE" == "--build" ]; then
	    echo "Building Sashimi images..."
        deploy_build_explorer
        echo "Building Sashimidb images..."
        deploy_build_database
    else
        deploy "$@"
    fi
}

#Pass arguments to function exactly as-is
main "$@"
