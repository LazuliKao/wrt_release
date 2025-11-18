base_image=$1
image_name=$2

if [ -z "$base_image" ] || [ -z "$image_name" ]; then
    echo "Usage: $0 <base_image> <image_name>"
    exit 1
fi
container_tmp_Dockerfile=$(mktemp Dockerfile.XXXXXX)
docker pull "$base_image"
container_default_user=$(docker run --rm "$base_image" whoami)
cat > "$container_tmp_Dockerfile" <<EOF
FROM $base_image
USER root
RUN apt-get update && apt-get install -y sudo git jq build-essential cmake g++ clang bison flex libelf-dev libncurses5-dev python3-distutils zlib1g-dev python3 pkg-config libssl-dev
USER $container_default_user
RUN git config --global pull.rebase false
RUN git config --global advice.detachedHead false
CMD ["bash", "build_container.sh", "$image_name"]
EOF
docker build -t "$image_name" -f "$container_tmp_Dockerfile" .
rm -f "$container_tmp_Dockerfile"