#!/bin/bash

# get user info for session
function getUser() {
   local tkn=$1
   local amount=$2
   local pause=$3
   for ((i=1;i<=amount;i++))
   do
      curl -k -X GET http://127.0.0.1:8080/realms/master/protocol/openid-connect/userinfo \
         --noproxy '*' -H "Accept: application/json" \
         -H "Authorization: Bearer $tkn" | jq .
      
      [[ -n $pause ]] && echo -e "\e[32mWait ${pause}s for next request..\e[0m" && sleep $pause;
   done
}

# create sessión in keycloak
function getToken() {
    TKN=$(curl -k -X POST http://127.0.0.1:8080/realms/master/protocol/openid-connect/token \
        -H "Content-application: Type/x-www-form-urlencoded" --noproxy '*' \
        -d "username=admin" \
        -d 'password=admin' \
        -d 'grant_type=password' \
        -d 'client_id=admin-cli' \
        -d 'scope=openid' \
        | jq -r '.access_token')
    echo $TKN
}

function stopKeycloak() {
    local num_instance=$1
    local keycloak_n="keycloak-${num_instance}"

    keycloak_id=$(docker ps -aqf "name=${keycloak_n}")
    docker stop $keycloak_id
    echo -e "\e[33mStop ${keycloak_n} id=${keycloak_id} \e[0m" >&2
    echo $keycloak_id
}

function findToContainerLog() {
    local find_text=$1
    local tail=$2
    local instance=$3

    # echo -e "\e[33mLogs instance ${instance} find $find_text & tail $tail \e[0m" >&2
    echo -e "$(exec bash -c "docker logs ${instance} --tail ${tail} 2>&1 | grep "${find_text}"")"
}

# Check Containers
# Print the message to stderr.
function checkRunning() {
    running="$(docker-compose ps --services --filter "status=running")"
    services="$(docker-compose ps --services)"
    if [ "$running" != "$services" ]; then
        echo -e "Following services are not running:" >&2
        # Bash specific
        comm -13 <(sort <<<"$running") <(sort <<<"$services")
        # 1 = false
        echo 1
    elif [ ! -n $services ]; then
        echo -e "\e[33mAll services are not running\e[0m" >&2
        echo 1
    else
        echo "All services are running" >&2
        # 0 = true
        echo 0
    fi
}

echo -e "\e[32mBEGIN Test..\e[0m"
export INSTANCES_KEYCLOAK=$(docker ps -a | grep keycloak/keycloak | awk "END{print NR}")
running=$(checkRunning)
# echo "${running}"
if [ $running -eq 0 ]; then
    # Pedir info a una sola instancia de keycloak
    iter=10
    echo -e "\e[32mGet user info iter=${iter} request..\e[0m"
    tkn=$(getToken)
    getUser $tkn $iter
    wait

    echo -e "\e[32mStop keycloak..\e[0m"
    num_instance=$(( ( RANDOM % $INSTANCES_KEYCLOAK )  + 1 ))
    stop_instance=$(stopKeycloak $num_instance)
    # echo -e "$(docker logs $stop_instance 2>&1 | grep "stopped in")"
    wait

    # Iniciar la instancia antes detenida
    echo -e "\e[32mStart keycloak $(docker start $stop_instance >& /dev/null)..\e[0m"
    wait

    iter=20
    echo -e "\e[32mGet user info iter=${iter} request..\e[0m"
    tkn=$(getToken)
    getUser $tkn iter 1
    wait

    # Log result
    echo -e "\e[32mLog proxy..\e[0m"
    echo -e "$(docker logs proxy --tail 60)"
    wait
    echo -e "\e[32mLog keycloak stop & start..\e[0m"
    f_stop="stopped in"
    findToContainerLog "$f_stop" 45 $stop_instance
    wait
    f_start="started in"
    findToContainerLog  "$f_start" 35 $stop_instance
else 
    echo "End abort" >&2
    exit 1
fi

echo -e "\e[32mEND Test OK\e[0m"
