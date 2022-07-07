#!/bin/bash
rm -rf gramine >/dev/null 2>&1

git clone --depth 1 https://github.com/gramineproject/gramine.git

cd gramine/CI-Examples/ra-tls-secret-prov
make clean && make dcap >/dev/null 2>&1
cd ../../../

# Getting cert input from the user:
echo ""
echo "Do you have certs to provide?"
echo "Please get familiar with the certificate format here: https://github.com/gramineproject/contrib/tree/master/Examples/aks-attestation/ssl"
echo "[Note: If you select 'n' then test certificates will be generated automatically with Common Name=localhost,"
echo "       and those must not be used in production ]"
echo -n "y/n: "
read -r cert_available
echo ""

while [[ "$cert_available" != "y"  && "$cert_available" != "n" ]];
do
    echo "You have entered a wrong option, please type y or n only"
    echo -n "y/n: "
    read -r cert_available
    echo ""
done

if [ "$cert_available" = "y" ]; then
    echo 'Please copy the certificates to gsc_image_curation/verifier_image/ssl folder'
    read -p 'Press any key to proceed -> '

    # Replacing autogenerated certificates with user provided certificates
    rm -rf gramine/CI-Examples/ra-tls-secret-prov/ssl >/dev/null 2>&1
    cp -r ssl gramine/CI-Examples/ra-tls-secret-prov/ssl
fi

# Copying ca.crt for the client application
cp gramine/CI-Examples/ra-tls-secret-prov/ssl/ca.crt ./

docker build -f verifier.dockerfile -t verifier_image .

rm -rf gramine >/dev/null 2>&1
