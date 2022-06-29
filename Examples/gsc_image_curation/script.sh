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
    echo "You have entered a wrong letter, please type r or p only"
    echo -n "r/p: "
    read -r start
done

if [ "$start" = "p" ]; then
    default_base_image="pytorch/pytorch"
    start="pytorch"
else
    default_base_image="redis:7.0.0"
    start="redis"
    entry_script=entry_script.sh
    entry_script_with_attestation=entry_script_with_attestation.sh
fi

app_image=$start"_image"
wrapper_dockerfile=$start".dockerfile"
app_image_manifest=$start".manifest"

# Putting encrypted files related placeholder in the manifest
sed -i '/{ path/d' $app_image_manifest
sed -i '/]  #encrypted_files/d' $app_image_manifest
sed -i 's|.*SECRET_PROVISION_SET_KEY.*|# loader.env.SECRET_PROVISION_SET_KEY = "default"|' $app_image_manifest
sed -i 's|.*fs.mounts.*|# Placeholder for encrypted_files|' $app_image_manifest

# Putting back Env variable placeholder
sed -i '/# User provided Env Variable/d' $app_image_manifest
sed -i "s|.*# User Provided Environment Variables.*|# Placeholder for environment variables|" $app_image_manifest


# Get Base image name
base_image=""
echo ""
echo "Kindly provide a base image name [default: "$default_base_image"]"
echo "[Note: Please ensure all the required files are part of the base image]"
read -p "Base image name [press ENTER for default] -> " base_image

if [ -z "${base_image}" ]; then
    echo "No base image provided by the user, going with the default image: "$default_base_image
    sed -i 's|From.*|From '$default_base_image'|' $wrapper_dockerfile
    base_image=$default_base_image
else
    while [ "$(docker images -q "$base_image" 2> /dev/null)" == "" ];
    do
        echo ""$base_image" is not present locally, hence fetching from dockerhub"
        docker pull $base_image
        if [[ "$(docker images -q "$base_image" 2> /dev/null)" == "" ]]; then
            read -p "Kindly provide a correct base image name -> " base_image
            if [ -z "${base_image}" ]; then
                base_image=$default_base_image
            fi
        fi
    done
    sed -i 's|From.*|From '$base_image'|' $wrapper_dockerfile
fi


# Signing key
echo ""
echo "Do you have a signing key (SGX requires RSA 3072 keys with public exponent equal to 3.)?"
echo "You can generate signing key using this command: openssl genrsa -3 -out enclave-key.pem 3072"
echo "If you select 'n' here , then the script will autogenerate a key using the above command"
echo -n "y/n: "
read -r signing_key_present

while [[ "$signing_key_present" != "y"  && "$signing_key_present" != "n" ]];
do
    echo "You have entered a wrong letter, please type y or n only"
    echo -n "y/n: "
    read -r signing_key_present
done

echo ""
signing_key_path=""
if [ "$signing_key_present" = "y" ]; then
    read -p "Kindly provide the path of the signing key here and copy the key -> " signing_key_path
    while [ ! -f "$signing_key_path" ]
    do
        echo "Error: "$signing_key_path" file does not exist."
        echo ""
        read -p "Kindly provide a correct key file with **absolute path** -> " signing_key_path
    done
else
    echo "Generating signing key"
    openssl genrsa -3 -out enclave-key.pem 3072
    signing_key_path="enclave-key.pem"
fi


# Get Attestation Input
echo ""
echo "Do you require ra-tls remote attestation (https://gramine.readthedocs.io/en/stable/attestation.html)?"
echo -n "y/n: "
read -r attestation_required
while [[ "$attestation_required" != "y" && "$attestation_required" != "n" ]];
do
    echo "You have entered a wrong letter, please type y or n only"
    echo -n "y/n: "
    read -r attestation_required
done
echo ""

if [ "$attestation_required" = "y" ]; then
    read -p "Kindly provide path to your verifier ca certificate (crt format only) -> " ca_cert_path
    while [ ! -f "$ca_cert_path" ]
    do
        echo "Error: "$ca_cert_path" file does not exist."
        read -p "Kindly provide a correct ca certificate file with **absolute path** (crt format only) -> " ca_cert_path
        echo ""
        echo "You have given the following ca cert path: "$ca_cert_path
    done
    echo ""
    cp $ca_cert_path ca.crt
    sed -i 's|.*crt.*|COPY ca.crt /ca.crt|' $wrapper_dockerfile
    sed -i 's|.*ENV ATTESTATION_REQUIRED.*|ENV ATTESTATION_REQUIRED="true"|' $wrapper_dockerfile
    sed -i 's|.*remote_attestation.*|sgx.remote_attestation = true|' $app_image_manifest
    sed -i 's|.*SECRET_PROVISION_CA_CHAIN_PATH.*|loader.env.SECRET_PROVISION_CA_CHAIN_PATH = "/ca.crt"|' $app_image_manifest
else
    sed -i 's|.*crt.*|# COPY ca.crt /ca.crt|' $wrapper_dockerfile
    sed -i 's|.*ENV ATTESTATION_REQUIRED.*|ENV ATTESTATION_REQUIRED="false"|' $wrapper_dockerfile
    sed -i 's|.*remote_attestation.*|# sgx.remote_attestation = true|' $app_image_manifest
    sed -i 's|.*SECRET_PROVISION_CA_CHAIN_PATH.*|# loader.env.SECRET_PROVISION_CA_CHAIN_PATH = "/ca.crt"|' $app_image_manifest
    sed -i 's|.*SECRET_PROVISION_SET_KEY.*|# loader.env.SECRET_PROVISION_SET_KEY = "default"|' $app_image_manifest
    sed -i '/{ path/d' $app_image_manifest
    sed -i '/]  #encrypted_files/d' $app_image_manifest
    sed -i 's|.*fs.mounts.*|# Placeholder for encrypted_files|' $app_image_manifest
fi

    
# Environment Variables:
echo "Do you have any runtime environment variables to provide?"
echo -n "y/n: "
read -r env_required

while [[ "$env_required" != "y"  && "$env_required" != "n" ]];
do
    echo "You have entered a wrong letter, please type y or n only"
    echo -n "y/n: "
    read -r env_required
done
echo ""

if [ "$env_required" = "y" ]; then
    read -p 'Kindly provide list of env variables and respective values separated by comma (accepted format: name="Xyz",age="20") -> ' envs
    IFS=',' #setting comma as delimiter
    read -a env_list <<<"$envs" #reading str as an array as tokens separated by IFS
    env_string_list='# User Provided Environment Variables\n'
    for i in "${env_list[@]}"
    do
        env_string='loader.env.'
        env_string+="$i"
        env_string+='  # User provided Env Variable'
        env_string_list+="$env_string"
        env_string_list+='\n'
    done
    echo ""
    sed -i 's|.*# Placeholder for environment variables.*|'$env_string_list'|' $app_image_manifest
fi


# Encrypted Files Section
if [ "$attestation_required" = "y" ]; then
    echo "Do you have encrypted files to add in the manifest?"
    echo "(Please get familiar with encrypted files here: https://gramine.readthedocs.io/en/stable/manifest-syntax.html#encrypted-files)"
    echo -n "y/n: "
    read -r encrypted_files_required

    while [[ "$encrypted_files_required" != "y"  && "$encrypted_files_required" != "n" ]];
    do
        echo "You have entered a wrong letter, please type y or n only"
        echo -n "y/n: "
        read -r encrypted_files_required
    done
    echo ""

    if [ "$encrypted_files_required" = "y" ]; then
        echo "Kindly provide list of valid encrypted file names (or path relative to workdir), separated by a semi colon."
        echo "Here, we will put base image workdir as a prefix to the filename or the path provided by the user."
        echo "Please provide the file names as referred by scripts in the base image."
        read -p "Accepted format: file1;path_relative_path/file2;file3 (e.g. classes.txt;app/result.txt) -> " ef_files
        IFS=';' #setting semi colon as delimiter
        read -a ef_files_list <<<"$ef_files"
        encrypted_files_string='fs.mounts = [\n'
        workdir_base_image="$(docker image inspect "$base_image" | jq '.[].Config.WorkingDir')"
        workdir_base_image=`sed -e 's/^"//' -e 's/"$//' <<<"$workdir_base_image"`
        for i in "${ef_files_list[@]}"
        do
            encrypted_files_string+='  { path = "'$workdir_base_image'/'
            encrypted_files_string+=$i'", '
            encrypted_files_string+='uri = "file:'
            encrypted_files_string+=$i'", '
            encrypted_files_string+='type = "encrypted" },\n'
        done
        encrypted_files_string+="] "
        sed -i 's|.*# Placeholder for encrypted_files.*|'$encrypted_files_string' #encrypted_files|' $app_image_manifest
        sed -i 's|.*SECRET_PROVISION_SET_KEY.*|loader.env.SECRET_PROVISION_SET_KEY = "default"|' $app_image_manifest
    fi
fi


# Generating wrapper for base image
echo ""
echo "******************************* Generating Wrapper Image for Base Image *******************************"
echo ""
docker rmi -f $app_image
docker build -f $wrapper_dockerfile -t $app_image .
echo ""
if [ "$attestation_required" = "y" ]; then
    rm ca.crt
fi
# Download gsc that has dcap already enabled
echo ""
#rm -rf gsc
#git clone https://github.com/gramineproject/gsc.git
#git clone https://github.com/veenasai2/gsc.git
#cd gsc
#git checkout gsc_with_dcap
#cd ../

cp $signing_key_path gsc/enclave-key.pem
cd gsc
cp config.yaml.template config.yaml

# Set SGX driver as dcap (this helps to generated an Azure compatible image)
sed -i 's|    Repository: ""|    Repository: "https://github.com/intel/SGXDataCenterAttestationPrimitives.git"|' config.yaml
sed -i 's|    Branch:     ""|    Branch:     "DCAP_1.11 \&\& cp -r driver/linux/* ."|' config.yaml

cp ../$app_image_manifest test/

# Delete already existing gsc image for the base image
docker rmi -f gsc-$app_image
docker rmi -f gsc-$app_image-unsigned

echo ""
echo "******************************* Building GSC Image *******************************"
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
        echo "docker run --device=/dev/sgx/enclave -e SECRET_PROVISION_SERVERS=<server-dns_name:port> -v /var/run/aesmd/aesm.socket:/var/run/aesmd/aesm.socket -it gsc-$app_image"
    else
        echo "You can run the gsc-"$app_image" using the below command: "
        echo "docker run --net=host --device=/dev/sgx/enclave -it gsc-$app_image"
    fi
fi

#rm -rf gsc
