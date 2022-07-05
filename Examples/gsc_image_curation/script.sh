#!/bin/bash

echo ""
echo "################################# Welcome to GSC Image Curation Script #################################"
echo ""
echo ""

echo "Current version of this script tested for redis and pytorch only"
echo "Please type r for redis and p for pytorch"
echo -n "r/p: "
read -r start

while [[ "$start" != "r"  && "$start" != "p" ]];
do
    echo "You have entered a wrong option, please type r or p only"
    echo -n "r/p: "
    read -r start
done

if [ "$start" = "p" ]; then
    start="pytorch"
else
    start="redis"
fi

wrapper_dockerfile=$start"-gsc.dockerfile"
app_image_manifest=$start".manifest"

# Bringing the dockerfile to default
sed -i 's|.*ca.crt.*|# COPY ca.crt /ca.crt|' $wrapper_dockerfile

# Bringing the manifest file to default
sed -i '0,/# Based on user input the manifest file will automatically be modified after this line/I!d' $app_image_manifest


# Get Base image name
base_image=""
echo ""
echo "Please specify a base image name"
echo "[Note: Please ensure all the files required for the image at runtime are part of the base image."
echo "       Gramine ignores any files that are passed as arguments during runtime.]"
read -p "Base image name -> " base_image

while [ -z "${base_image}" ];
do
    read -p "No base image provided by the user, please provide a valid base image -> " base_image
done

while [ "$(docker images -q "$base_image" 2> /dev/null)" == "" ];
    do
        echo ""$base_image" is not present locally, hence fetching from dockerhub"
        docker pull $base_image
        if [[ "$(docker images -q "$base_image" 2> /dev/null)" == "" ]]; then
            read -p "Please specify a correct base image name -> " base_image
            while [ -z "${base_image}" ];
            do
                read -p "No base image provided by the user, please provide a valid base image -> " base_image
            done
        fi
    done
sed -i 's|From.*|From '$base_image'|' $wrapper_dockerfile

app_image=$base_image"-wrapper"

# Signing key
echo ""
echo "Do you have a signing key (SGX requires RSA 3072 keys with public exponent equal to 3.)?"
echo "You can generate signing key using this command: openssl genrsa -3 -out enclave-key.pem 3072"
echo "If you select 'n' here , then the script will autogenerate a key using the above command"
echo -n "y/n: "
read -r signing_key_present

while [[ "$signing_key_present" != "y"  && "$signing_key_present" != "n" ]];
do
    echo "You have entered a wrong option, please type y or n only"
    echo -n "y/n: "
    read -r signing_key_present
done

echo ""
signing_key_path=""
if [ "$signing_key_present" = "y" ]; then
    read -p "Please specify path to the signing key here -> " signing_key_path
    while [ ! -f "$signing_key_path" ]
    do
        echo "Error: "$signing_key_path" file does not exist."
        echo ""
        read -p "Please specify a correct key file with **absolute path** -> " signing_key_path
    done
else
    echo "Generating signing key"
    openssl genrsa -3 -out enclave-key.pem 3072
    signing_key_path="enclave-key.pem"
fi


# Get Attestation Input
echo ""
echo "Do you require remote attestation (DCAP)(https://gramine.readthedocs.io/en/stable/attestation.html)?"
echo "[Note: attestation is required for gramine to process encrypted files]"
echo -n "y/n: "
read -r attestation_required
while [[ "$attestation_required" != "y" && "$attestation_required" != "n" ]];
do
    echo "You have entered a wrong option, please type y or n only"
    echo -n "y/n: "
    read -r attestation_required
done
echo ""

if [ "$attestation_required" = "y" ]; then
    read -p "Please specify path to your verifier ca certificate (crt format only) -> " ca_cert_path
    while [ ! -f "$ca_cert_path" ]
    do
        echo "Error: "$ca_cert_path" file does not exist."
        read -p "Please specify a correct ca certificate file with **absolute path** (crt format only) -> " ca_cert_path
        echo ""
        echo "You have given the following ca cert path: "$ca_cert_path
    done
    echo ""
    cp $ca_cert_path ca.crt
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
    allowed_files=$'sgx.allowed_files = [\n"file:/etc/host.conf",\n"file:/etc/hosts",\n"file:/etc/resolv.conf",\n]'
    echo "$allowed_files">> $app_image_manifest
fi

# Environment Variables:
echo "Do you have any runtime environment variables to provide?"
echo "[Note: Gramine will ignore any env specified at runtime, so please ensure you provide that here only]"
echo -n "y/n: "
read -r env_required

while [[ "$env_required" != "y"  && "$env_required" != "n" ]];
do
    echo "You have entered a wrong option, please type y or n only"
    echo -n "y/n: "
    read -r env_required
done
echo ""

if [ "$env_required" = "y" ]; then
    read -p 'Please specify a list of env variables and respective values separated by comma (accepted format: name="Xyz",age="20") -> ' envs
    IFS=',' #setting comma as delimiter
    read -a env_list <<<"$envs" #reading str as an array as tokens separated by IFS
    echo '' >> $app_image_manifest
    echo '# User Provided Environment Variables' >> $app_image_manifest
    for i in "${env_list[@]}"
    do
        env_string='loader.env.'
        env_string+=$i
	echo "$env_string" >> $app_image_manifest
    done
    echo ""
fi


# Encrypted Files Section
if [ "$attestation_required" = "y" ]; then
    echo "Do you have encrypted files to add in the manifest?"
    echo "(Please get familiar with encrypted files here: https://gramine.readthedocs.io/en/stable/manifest-syntax.html#encrypted-files)"
    echo -n "y/n: "
    read -r encrypted_files_required

    while [[ "$encrypted_files_required" != "y"  && "$encrypted_files_required" != "n" ]];
    do
        echo "You have entered a wrong option, please type y or n only"
        echo -n "y/n: "
        read -r encrypted_files_required
    done
    echo ""

    if [ "$encrypted_files_required" = "y" ]; then
        echo "Please specify list of valid encrypted file names (or path relative to workdir), separated by a semi colon."
        echo "Here, we will put base image workdir as a prefix to the filename or the path provided by the user."
        echo "Please provide the file names as referred by scripts in the base image."
        read -p "Accepted format: file1;path_relative_path/file2;file3 (e.g. classes.txt;app/result.txt) -> " ef_files
        IFS=';' #setting semi colon as delimiter
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
fi


# Generating wrapper for base image
echo ""
echo "******************************* Generating Wrapper Image for Base Image *******************************"
echo ""
docker rmi -f $app_image >/dev/null 2>&1
docker build -f $wrapper_dockerfile -t $app_image .
echo ""
if [ "$attestation_required" = "y" ]; then
    rm ca.crt
fi
# Download gsc that has dcap already enabled
echo ""
rm -rf gsc >/dev/null 2>&1
# git clone https://github.com/gramineproject/gsc.git

# Todo: Remove these steps once https://github.com/gramineproject/gsc/pull/70
git clone https://github.com/aneessahib/gsc.git
cd gsc
git checkout builddcap
cd ../

cp $signing_key_path gsc/enclave-key.pem

# delete the signing key created by the script
rm enclave-key.pem >/dev/null 2>&1

cd gsc
cp config.yaml.template config.yaml

# ToDo: Remove these two lines once https://github.com/gramineproject/gramine/pull/722 and https://github.com/gramineproject/gramine/pull/721 merged
sed -i 's|    Repository: "https://github.com/gramineproject/gramine.git"|    Repository: "https://github.com/aneessahib/gramine.git"|' config.yaml
sed -i 's|v1.2|secret_prov|' config.yaml

# Set SGX driver as dcap (this helps to generated an Azure compatible image)
sed -i 's|    Repository: ""|    Repository: "https://github.com/intel/SGXDataCenterAttestationPrimitives.git"|' config.yaml
sed -i 's|    Branch:     ""|    Branch:     "DCAP_1.11 \&\& cp -r driver/linux/* ."|' config.yaml

cp ../$app_image_manifest test/

# Delete already existing gsc image for the base image
docker rmi -f gsc-$app_image >/dev/null 2>&1
docker rmi -f gsc-$app_image-unsigned >/dev/null 2>&1

echo ""
echo "******************************* GSC Image is ready to run *******************************"
echo ""

./gsc build $app_image  test/$app_image_manifest
echo ""
echo ""
./gsc sign-image $app_image enclave-key.pem

cd ../
if [[ "$(docker images -q "gsc-$app_image" 2> /dev/null)" == "" ]]; then
    echo ""
    echo ""
    echo ""gsc-$app_image" creation failed, exiting .... "
    echo ""
    exit 1
else
    echo ""
    echo ""
    echo "#################### We are going to run the "gsc-$app_image" image ####################"
    echo ""
    echo ""
    if [ "$attestation_required" = "y" ]; then
        echo "Please ensure your remote attestation verifier is ready to accept the connection **from this device/container**"
        echo "Also, the ca certificate for the verifier should be same as what you have given in the beginning of the script"
        echo""
        echo "You can run the gsc-"$app_image" using the below command:"
	echo "Please use --net=host also with the below commmand, if the verifier is running on localhost"
        echo "docker run --device=/dev/sgx/enclave -e SECRET_PROVISION_SERVERS=<server-dns_name:port> -v /var/run/aesmd/aesm.socket:/var/run/aesmd/aesm.socket -it gsc-$app_image"
    else
        echo "You can run the gsc-"$app_image" using the below command: "
        echo "docker run  --device=/dev/sgx/enclave -it gsc-$app_image"
    fi
fi

rm -rf gsc >/dev/null 2>&1
