#!/bin/bash

if [ "$ATTESTATION_REQUIRED" = "true" ]; then
    if [ -z "${SECRET_PROVISION_SECRET_STRING}" ]; then
        echo "Remote Attestation failed. Cannot start the redis server"
        exit 1
    fi
fi
/usr/local/bin/docker-entrypoint.sh /usr/local/bin/redis-server --save '' --protected-mode no  #main command
