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
: "${QEMU_GIT_REPO:=multiarch/qemu-user-static}"
: "${HUB:=}"
: "${CLEAN:=}" # Weather or not to clean local docker registry
: "${PUSH:=}" #Weather or not push the docker images to the HUB

#---------------------------------------------------------------------------------------------------------------------------
# FUNCTIONS
#---------------------------------------------------------------------------------------------------------------------------
function _info  () { printf "\\r[ \\033[00;34mINFO\\033[0m ] %s\\n" "$@"; }
function _warn  () { printf "\\r\\033[2K[ \\033[0;33mWARN\\033[0m ] %s\\n" "$@"; }
function _error () { printf "\\r\\033[2K[ \\033[0;31mFAIL\\033[0m ] %s\\n" "$@"; }
function _debug () { printf "\\r[ \\033[00;37mDBUG\\033[0m ] %s\\n" "$@"; }

function usage() {
    echo -e "\nusage: $0 [--arch <arch> | --hub [--arch <arch>]]"
    echo -e ""
    echo -e "  General parameters:"
    echo -e "    --arch           only create an image or a spcific arch (amd64, arm32v6 and arm64v8)."
    echo -e "    --hub            Docker Hub where to push the images to."
    echo -e "    --push           enable push to docker docker hub specified."
    echo -e "    --clean          enable local docker registry clean as final step."
    echo -e "    --debug          debug mode."
    echo -e "    -?               help."
    exit 0
}

function _pre_reqs() {
  _info "Creating temporary directory..."
  mkdir -p ./tmp/{qemu,app}
}

function _update_qemu() {
  qemu_release=$(curl -Ssl "https://api.github.com/repos/${QEMU_GIT_REPO}/releases/latest" | jq -r .tag_name)
  _info "Downloading latest Qemu release: ${qemu_release}."
  pushd ./tmp/qemu
  for docker_arch in ${ARCH_ARR}; do
      case ${docker_arch} in
      amd64       ) qemu_arch="x86_64" ;;
      arm32v6     ) qemu_arch="arm" ;;
      arm64v8     ) qemu_arch="aarch64" ;;
      *)
        _error "Unknown target architechture."
        exit 1
    esac
    if [[ ! -f qemu-${qemu_arch}-static ]]; then
      wget -N https://github.com/"${QEMU_GIT_REPO}"/releases/download/"${qemu_release}"/qemu-"${qemu_arch}"-static.tar.gz
      tar -xf qemu-"${qemu_arch}"-static.tar.gz
      rm -rf qemu-"${qemu_arch}"-static.tar.gz
    fi
  done
  popd
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

	sed -i "s|__QEMU_ARCH__|${qemu_arch}|g" Dockerfile."${docker_arch}"

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

    if [[ "${docker_arch}" == "amd64" ]]; then
      docker build -f Dockerfile."${docker_arch}" -t "${DOCKER_HUB_REPO}":latest .
    else
      docker build -f Dockerfile."${docker_arch}" -t "${DOCKER_HUB_REPO}":"${docker_arch}"-latest .
    fi
	done
}

function _push_docker_images() {
  _info "Pushing Docker images to the Docker HUB..."
  for docker_arch in ${ARCH_ARR}; do
    _info "Pushing Docker images for: ${docker_arch}."
    if [[ "${docker_arch}" == "amd64" ]]; then
      docker push "${DOCKER_HUB_REPO}":latest
    else
      docker push "${DOCKER_HUB_REPO}":"${docker_arch}"-latest
    fi
  done
}

function _cleanup () {
  _info "Cleaning up temporary files..."
  rm -rf ./tmp
  #docker images -q | xargs docker rmi -f
  for docker_arch in ${ARCH_ARR}; do
    if [[ "${docker_arch}" == "amd64" ]]; then
      docker rmi "${DOCKER_HUB_REPO}":latest
    else
      docker rmi "${DOCKER_HUB_REPO}":"${docker_arch}"-latest
    fi

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
      --arch )         shift&&ARCH_ARR=$1;;
      --hub )          HUB=hub;;
      --clean )        CLEAN=true;;
      --push )         PUSH=true;;
      --debug )        DEBUG=true;;
      -? | --help )    usage && exit ;;
      * )              usage && exit 1 ;;
    esac
    shift
done

[[ "${DEBUG}" == 'true' ]] && set -o xtrace

_info "Generating Docker Hub images for ${ARCH_ARR}"
_pre_reqs
_update_qemu
_generate_docker_files
_build_docker_images

if [[ ! -z "${PUSH}" ]]; then
  _push_docker_images
fi
	
if [[ ! -z "${CLEAN}" ]]; then
  _cleanup
fi
