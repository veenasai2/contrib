From redis:7.0.0

COPY ca.crt /ca.crt

ENV ATTESTATION_REQUIRED="true"

# These two lines are required as redis has a script entrypoint (https://github.com/gramineproject/graphene/issues/1728)
COPY entry_script_redis.sh /usr/local/bin/entry_script_redis.sh
ENTRYPOINT ["/bin/bash", "/usr/local/bin/entry_script_redis.sh"]


