#!/bin/bash

if [ $# != 2 ] ; then
        echo "Expected format ./curation_script_for_test_image.sh redis redis:7.0.0"
        exit 1
fi

start=$1
cd $start
wrapper_dockerfile=$start"-gsc.dockerfile"
app_image_manifest=$start".manifest"

# Bringing the dockerfile to default
sed -i 's|.*ca.crt.*|# COPY ca.crt /ca.crt|' $wrapper_dockerfile

# Bringing the manifest file to default
sed -i '0,/# Based on user input the manifest file will automatically be modified after this line/I!d' $app_image_manifest

base_image=$2
sed -i 's|From.*|From '$base_image'|' $wrapper_dockerfile
app_image=$base_image"-wrapper"
echo ""

docker rmi -f $app_image >/dev/null 2>&1
docker build -f $wrapper_dockerfile -t $app_image .

# Exit from $start directory
cd ..

# Download gsc that has dcap already enabled
echo ""
rm -rf gsc >/dev/null 2>&1
# git clone https://github.com/gramineproject/gsc.git

# Todo: Remove these steps once https://github.com/gramineproject/gsc/pull/70
git clone https://github.com/aneessahib/gsc.git
cd gsc
git checkout binary_path

cp config.yaml.template config.yaml
openssl genrsa -3 -out enclave-key.pem 3072
# ToDo: Remove these two lines once https://github.com/gramineproject/gramine/pull/722 and https://github.com/gramineproject/gramine/pull/721 merged
sed -i 's|    Repository: "https://github.com/gramineproject/gramine.git"|    Repository: "https://github.com/aneessahib/gramine.git"|' config.yaml
sed -i 's|v1.2|script_secret2|' config.yaml

# Set SGX driver as dcap (this helps to generated an Azure compatible image)
sed -i 's|    Repository: ""|    Repository: "https://github.com/intel/SGXDataCenterAttestationPrimitives.git"|' config.yaml
sed -i 's|    Branch:     ""|    Branch:     "DCAP_1.11 \&\& cp -r driver/linux/* ."|' config.yaml

cp ../$start/$app_image_manifest test/

# Delete already existing gsc image for the base image
docker rmi -f gsc-$app_image >/dev/null 2>&1
docker rmi -f gsc-$app_image-unsigned >/dev/null 2>&1

./gsc build $app_image  test/$app_image_manifest
echo ""
echo ""
./gsc sign-image $app_image enclave-key.pem

# Exit from gsc directory
cd ../
rm -rf gsc >/dev/null 2>&1
if [[ "$(docker images -q "gsc-$app_image" 2> /dev/null)" == "" ]]; then
    echo ""
    echo ""
    echo ""gsc-$app_image" creation failed, exiting .... "
    echo ""
    exit 1
else
    echo ""
    echo "You can run the gsc-"$app_image" using the below command: "
    echo ""
    echo "docker run  --device=/dev/sgx/enclave -it gsc-$app_image"
fi
exit 1




