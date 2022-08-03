#!/bin/bash

docker-entrypoint.sh redis-server --save '' --protected-mode no  #main command
