#!/bin/bash

#CONTAINER_ID=$(docker ps -aqf "ancestor=quay.io/infinispan/server:14.0.19.Final")
CONTAINER_ID=$(docker ps -a | grep infinispan/server | awk {'print $1'})

USER_NAME=$1
[[ ! -n  $USER_NAME ]] && USER_NAME=admin
USER_PASS=$2
[[ ! -n  $USER_PASS ]] && USER_PASS=admin

RUN_FIND_LABEL=$3
[[ ! -n  $RUN_FIND_LABEL ]] && RUN_FIND_LABEL="Infinispan Server 14.0.19.Final started in"

echo -e "\e[33mParams in order:\n 1 USER_NAME=${USER_NAME}\n 2 USER_PASS=${USER_PASS}\n 3 RUN_FIND_LABEL=${RUN_FIND_LABEL}\n \e[0m"

if [ "$( docker container inspect -f '{{.State.Running}}' $CONTAINER_ID )" == "true" ]; then
    # Container correct startup check
    i=0
    to=5
    while [ $i -le $to ]; do
        RUN_FIND=$(docker logs $CONTAINER_ID 2>&1 | grep "$RUN_FIND_LABEL")
        if [ -n "$RUN_FIND" ]; then
            break
        fi
        echo -e "Waiting for a Container log \e[33mgrep\e[0m \e[32m${RUN_FIND_LABEL}\e[0m ..$i-$to"
        sleep 2
        #((i++))
        i=$((i+1))
        if [ $i -eq $to ]; then
            read -p "Keep waiting [s|y]? " -n 1 -r
            echo    # (optional) move to a new line
            if [[ $REPLY =~ ^[YySs]$ ]]
            then
                i=0
            else
                break
            fi
        fi
    done
    if [ ! -n "$RUN_FIND" ]; then
        echo -e "\e[31mThere is not Container started successfully\e[0m(solve: rerun)"
        exit 1
    fi

    if [ ! -n "$(docker exec $CONTAINER_ID sh -c 'cat server/conf/users.properties' | grep -e $USER_NAME)" ]; then
        echo -e "Create user infinispan with cli.sh"
        docker exec $(docker ps -aqf "ancestor=quay.io/infinispan/server:14.0.19.Final") sh -c "./bin/cli.sh user create $USER_NAME -p $USER_PASS -g $USER_NAME"
        # exit 0
    else
        echo -e "The user \e[32m${USER_NAME}\e[0m exists!"
    fi
else 
    echo -e "\e[31mContainer is not running\e[0m"
    exit 1
fi
