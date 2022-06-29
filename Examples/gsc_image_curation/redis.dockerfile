From redis:7.0.0

# COPY ca.crt /ca.crt

ENV ATTESTATION_REQUIRED="false"

# Todo please remove this once PR:https://github.com/gramineproject/gsc/pull/70 get merged
COPY libsecret_prov_attest.so /

# These two lines are required as redis has a script entrypoint (https://github.com/gramineproject/graphene/issues/1728)
COPY entry_script_redis.sh /usr/local/bin/entry_script_redis.sh
ENTRYPOINT ["/bin/bash", "/usr/local/bin/entry_script_redis.sh"]


