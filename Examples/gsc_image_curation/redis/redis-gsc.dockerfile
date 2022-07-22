From

# COPY ca.crt /ca.crt

# These two lines are required to include the necessary args for redis server (https://github.com/gramineproject/gramine/blob/master/CI-Examples/redis/README.md#why-this-redis-configuration)
# ToDo: remove the below two lines once a PR solving this issue https://github.com/gramineproject/gramine/issues/761 will be merged
COPY entry_script_redis.sh /usr/local/bin/entry_script_redis.sh
ENTRYPOINT ["/bin/bash", "/usr/local/bin/entry_script_redis.sh"]
