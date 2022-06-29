#!/bin/bash

if [ "$ATTESTATION_REQUIRED" = "true" ]; then
    if [ -z "${SECRET_PROVISION_SECRET_STRING}" ]; then
        echo "Remote Attestation failed. Cannot start the redis server"
        exit 1
    fi
fi
python3 pytorchexample.py  #main command
