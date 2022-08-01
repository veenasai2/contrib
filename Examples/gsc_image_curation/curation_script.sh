#!/bin/bash


if [ $# != 9 ] ; then
        echo "Expected 9 parameters"
        exit 1
fi

start=$1
wrapper_dockerfile=$start"-gsc.dockerfile"
app_image_manifest=$start".manifest"

cd $start

# Bringing the dockerfile to default
sed -i 's|.*ca.crt.*|# COPY ca.crt /ca.crt|' $wrapper_dockerfile

# Bringing the manifest file to default
sed -i '0,/# Based on user input the manifest file will automatically be modified after this line/I!d' $app_image_manifest


# Set base image name in the dockerfile
base_image="$2"
sed -i 's|From.*|From '$base_image'|' $wrapper_dockerfile

app_image=$base_image"-wrapper"

# Signing key
echo ""
signing_key_path="$3"
if [ "$signing_key_path" = "test-key" ]; then
    echo "Generating signing key"
    #Exiting $start directory as we want enclave key to be present in $gsc_image_creation directory
    cd ..
    openssl genrsa -3 -out enclave-key.pem 3072
    signing_key_path="enclave-key.pem"
    cd $start
fi

# Get Attestation Input
attestation_required=$4

if [ "$attestation_required" = "y" ]; then

    ca_cert_path=$5
    cd ../  #exiting start directory as the path to the ca cert can be w.r.t to gsc_image_curation directory
    cp $ca_cert_path $start/ca.crt
    cd $start
    sed -i 's|.*ca.crt.*|COPY ca.crt /ca.crt|' $wrapper_dockerfile
    echo '' >> $app_image_manifest
    echo '# Attestation related entries' >> $app_image_manifest
    echo 'sgx.remote_attestation = "dcap"' >> $app_image_manifest
    echo 'loader.env.LD_PRELOAD = "/gramine/meson_build_output/lib/x86_64-linux-gnu/libsecret_prov_attest.so"' >> $app_image_manifest
    echo 'loader.env.SECRET_PROVISION_SERVERS = { passthrough = true }' >> $app_image_manifest
    echo 'loader.env.SECRET_PROVISION_CONSTRUCTOR = "1"' >> $app_image_manifest
    echo 'loader.env.SECRET_PROVISION_CA_CHAIN_PATH = "/ca.crt"' >> $app_image_manifest
    echo '# loader.env.SECRET_PROVISION_SET_KEY = "default"' >> $app_image_manifest
    echo '' >> $app_image_manifest
    allowed_files=$'sgx.allowed_files = [\n"file:/etc/resolv.conf",\n]'
    echo "$allowed_files">> $app_image_manifest
fi

# Environment Variables:
env_required=$6

if [ "$env_required" = "y" ]; then
    envs=$7
    IFS=',' #setting comma as delimiter
    read -a env_list <<<"$envs" #reading str as an array as tokens separated by IFS
    echo '' >> $app_image_manifest
    echo '# User Provided Environment Variables' >> $app_image_manifest
    for i in "${env_list[@]}"
    do
        env_string='loader.env.'
	IFS='='
	read -a env <<<"$i"
        env_string+=${env[0]}'="'
	env_string+=${env[1]}'"'
	echo "$env_string" >> $app_image_manifest
    done
    echo ""
fi


# Encrypted Files Section
encrypted_files_required=$8

if [ "$encrypted_files_required" = "y" ]; then
        ef_files=$9
        IFS=':' #setting colon as delimiter
        read -a ef_files_list <<<"$ef_files"
        echo '' >> $app_image_manifest
        echo '# User Provided Encrypted files' >> $app_image_manifest
        echo 'fs.mounts = [' >> $app_image_manifest
        workdir_base_image="$(docker image inspect "$base_image" | jq '.[].Config.WorkingDir')"
        workdir_base_image=`sed -e 's/^"//' -e 's/"$//' <<<"$workdir_base_image"`
        for i in "${ef_files_list[@]}"
        do
                encrypted_files_string=''
                encrypted_files_string+='  { path = "'$workdir_base_image'/'
                encrypted_files_string+=$i'", '
                encrypted_files_string+='uri = "file:'
                encrypted_files_string+=$i'", '
                encrypted_files_string+='type = "encrypted" },'
                echo "$encrypted_files_string" >> $app_image_manifest
        done
        echo "]" >> $app_image_manifest
        sed -i 's|.*SECRET_PROVISION_SET_KEY.*|loader.env.SECRET_PROVISION_SET_KEY = "default"|' $app_image_manifest
fi


# Generating wrapper for base image

docker rmi -f $app_image >/dev/null 2>&1
docker build -f $wrapper_dockerfile -t $app_image .
echo ""
if [ "$attestation_required" = "y" ]; then
    rm ca.crt
fi

# Exit from $start directory
cd ..

# Download gsc that has dcap already enabled
echo ""
rm -rf gsc >/dev/null 2>&1

git clone https://github.com/gramineproject/gsc.git

cp $signing_key_path gsc/enclave-key.pem

# delete the signing key created by the script
rm enclave-key.pem >/dev/null 2>&1

cd gsc
cp config.yaml.template config.yaml

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

echo ""

./gsc build $app_image  test/$app_image_manifest
echo ""
echo ""
./gsc sign-image $app_image enclave-key.pem

cd ../
rm -rf gsc >/dev/null 2>&1
