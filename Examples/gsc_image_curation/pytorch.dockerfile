From

COPY ca.crt /ca.crt

ENV ATTESTATION_REQUIRED="true"

COPY entry_script_pytorch.sh /usr/local/bin/entry_script_pytorch.sh
ENTRYPOINT ["/bin/bash", "/usr/local/bin/entry_script_pytorch.sh"]

