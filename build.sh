#!/bin/bash
# docker build --rm=true -t coppit/no-ip . 
set -o errexit
set -o pipefail
set -o nounset

#---------------------------------------------------------------------------------------------------------------------------
# VARIABLES
#---------------------------------------------------------------------------------------------------------------------------
: "${DEBUG:=false}"
: "${ARCH_ARR:=amd64 arm32v6 arm64v8}"
: "${DOCKER_HUB_REPO:=jorkzijlstra/no-ip}"
: "${LOCAL:=}"
: "${HUB:=}"


#---------------------------------------------------------------------------------------------------------------------------
# FUNCTIONS
#---------------------------------------------------------------------------------------------------------------------------
function _info  () { printf "\\r[ \\033[00;34mINFO\\033[0m ] %s\\n" "$@"; }
function _warn  () { printf "\\r\\033[2K[ \\033[0;33mWARN\\033[0m ] %s\\n" "$@"; }
function _error () { printf "\\r\\033[2K[ \\033[0;31mFAIL\\033[0m ] %s\\n" "$@"; }
function _debug () { printf "\\r[ \\033[00;37mDBUG\\033[0m ] %s\\n" "$@"; }

function usage() {
    echo -e "\nusage: $0 [--local --arch <arch> | --hub [--arch <arch>]]"
    echo -e ""
    echo -e "  General parameters:"
    echo -e "    --local          generates a local test image for amd64, arm32v6 or arm64v8."
    echo -e "    --arch           required for local test images, optional for hub images."
    echo -e "    --hub            generates amd64, arm32v6 and arm64v8 Docker images and pushes them to the Docker Hub"
    echo -e "    --debug          debug mode."
    echo -e "    -?               help."
    exit 0
}

function _generate_docker_files() {
	_info "Generating docker file for $ARCH_ARR"
	for docker_arch in amd64 arm32v6 arm64v8; do
	case ${docker_arch} in
		amd64   ) qemu_arch="x86_64" ;;
		arm32v6 ) qemu_arch="arm" ;;
		arm64v8 ) qemu_arch="aarch64" ;;    
	esac

	cp Dockerfile.cross Dockerfile.${docker_arch}

	# sed -i "s|__QEMU_ARCH__|${qemu_arch}|g" Dockerfile."${docker_arch}"

    if [[ ${docker_arch} == "amd64" ]]; then
      sed -i "s/__BASEIMAGE_ARCH__\///g" Dockerfile."${docker_arch}"
    else
      sed -i "s|__BASEIMAGE_ARCH__|${docker_arch}|g" Dockerfile."${docker_arch}"
    fi
	done
}

function _build_docker_images() {
	_info "Building Docker images..."
	for docker_arch in ${ARCH_ARR}; do
		_info "Building Docker images for: ${docker_arch}"

		docker build -f Dockerfile."${docker_arch}" -t "${DOCKER_HUB_REPO}":"${docker_arch}"-latest .
		
		# docker tag "${DOCKER_HUB_REPO}":"${docker_arch}"-latest "${DOCKER_HUB_REPO}":test-"${docker_arch}"-latest
		# if [[ "${docker_arch}" == "amd64" ]]; then
			# docker tag "${DOCKER_HUB_REPO}":"${docker_arch}"-latest "${DOCKER_HUB_REPO}":latest
			# docker tag "${DOCKER_HUB_REPO}":"${docker_arch}"-latest "${DOCKER_HUB_REPO}":test-latest
		# fi
	done
}

function _cleanup () {
  _info "Cleaning up temporary files..."
  rm -rf ./tmp
  docker images -q | xargs docker rmi -f
  for docker_arch in ${ARCH_ARR}; do
    [[ -f Dockerfile."${docker_arch}" ]] && rm -rf Dockerfile."${docker_arch}"
    continue
  done
}

#---------------------------------------------------------------------------------------------------------------------------
# MAIN
#---------------------------------------------------------------------------------------------------------------------------
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case $1 in
      --local )        LOCAL=local&&ARCH_ARR='';;
      --arch )         shift&&ARCH_ARR=$1;;
      --hub )          HUB=hub;;
      --debug )        DEBUG=true;;
      -? | --help )    usage && exit ;;
      * )              usage && exit 1 ;;
    esac
    shift
done

[[ "${DEBUG}" == 'true' ]] && set -o xtrace

if [[ ! -z "${LOCAL}" ]]; then
	_info "Generating local Docker image for ${ARCH_ARR}"
	[[ -z "${ARCH_ARR}" ]] && _error "Option --arch not specified!" && exit 1
	_generate_docker_files
	_build_docker_images
	# _cleanup
fi

if [[ ! -z "${HUB}" ]]; then
	_info "Generating Docker Hub images for ${ARCH_ARR}"
fi
	
