From pytorch/pytorch

# COPY ca.crt /ca.crt

COPY libsecret_prov_attest.so /

ENV ATTESTATION_REQUIRED="false"

COPY entry_script_pytorch.sh /usr/local/bin/entry_script_pytorch.sh
ENTRYPOINT ["/bin/bash", "/usr/local/bin/entry_script_pytorch.sh"]

