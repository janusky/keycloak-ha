# keycloak-ha

Running [Keycloak](https://quay.io/repository/keycloak/keycloak) in high availability mode using [distributed cache](https://www.keycloak.org/server/caching) with [Infinispan] instance (https://infinispan.org/) and a [Nginx](https://nginx.org/) as a load balancer.

* Inspirado en https://github.com/olivierboudet/keycloak-infinispan-jdbc

**CONTENT**

- [keycloak-ha](#keycloak-ha)
  - [Features](#features)
  - [Objetive](#objetive)
  - [Run](#run)
  - [Test](#test)
    - [Test Script Bash](#test-script-bash)
    - [Test Console](#test-console)
  - [TODO](#todo)
  - [Links](#links)

## Features

Instances

* Keycloak x 2 - quay.io/keycloak/keycloak:22.0.1
* Infinispan Cache - quay.io/infinispan/server:14.0.19.Final
* Postgres Database - postgres:15.4
* Nginx load balancer - jwilder/nginx-proxy:1.3.1

## Objetive

Have more than one Keycloak instance and both share the sessions established in any of the instances.  
Monitor the sessions created in the Infinispan instance.

## Run

>NOTA
>Run infinispan and postgres for then create an access user for infinispan.

```sh
# Rim postgres and infinispan
docker-compose up -d postgres infinispan

# Create user for access infinispan
# docker exec $(docker ps -aqf "ancestor=quay.io/infinispan/server:14.0.19.Final") sh -c './bin/cli.sh user create admin -p admin -g admin'
./infinispan_user.sh admin admin
`
http://127.0.0.1:11222/ - Open the console -> admin/admin
`
# Run tow instances keycloak
docker-compose up -d --scale keycloak=2

# Logs all: docker-compose logs -f
docker-compose logs -f infinispan
docker-compose logs -f keycloak
docker-compose logs -f nginx
```

## Test

An access token is created and then the user's in-session information is requested with the provided token.

You can choose to test in the console by observing each executed statement or invoke the execution of a bash script.

* [Test Console](#test-console)
* [Test Script Bash](#test-script-bash)

### Test Script Bash

In the file [test.sh](test.sh) a bash script was coded to perform a series of tests similar to those in [Test Console](#test-console).

```sh
bash test.sh
```

### Test Console

Test client_id admin-cli

```sh
# Get Access Token
export TKN=$(curl -k -X POST http://127.0.0.1:8080/realms/master/protocol/openid-connect/token \
    -H "Content-application: Type/x-www-form-urlencoded" --noproxy '*' \
    -d "username=admin" \
    -d 'password=admin' \
    -d 'grant_type=password' \
    -d 'client_id=admin-cli' \
    -d 'scope=openid' \
    | jq -r '.access_token')

# Get IDP userinfo x 10
for ((i=1;i<=10;i+=1)) 
do 
   curl -k -X GET http://127.0.0.1:8080/realms/master/protocol/openid-connect/userinfo \
         --noproxy '*' -H "Accept: application/json" \
         -H "Authorization: Bearer $TKN" | jq .
done

# Check log result example
# See session requests in different Keycloak instances
docker-compose logs -f nginx --tail 11
`
proxy  | nginx.1     | 127.0.0.1 172.19.0.1 - - [01/Nov/2023:18:53:57 +0000] "POST /realms/master/protocol/openid-connect/token HTTP/1.1" 200 2855 "-" "curl/7.68.0" "172.19.0.4:8080"
proxy  | nginx.1     | 127.0.0.1 172.19.0.1 - - [01/Nov/2023:18:53:59 +0000] "GET /realms/master/protocol/openid-connect/userinfo HTTP/1.1" 200 98 "-" "curl/7.68.0" "172.19.0.6:8080"
proxy  | nginx.1     | 127.0.0.1 172.19.0.1 - - [01/Nov/2023:18:54:00 +0000] "GET /realms/master/protocol/openid-connect/userinfo HTTP/1.1" 200 98 "-" "curl/7.68.0" "172.19.0.4:8080"
proxy  | nginx.1     | 127.0.0.1 172.19.0.1 - - [01/Nov/2023:18:54:00 +0000] "GET /realms/master/protocol/openid-connect/userinfo HTTP/1.1" 200 98 "-" "curl/7.68.0" "172.19.0.6:8080"
proxy  | nginx.1     | 127.0.0.1 172.19.0.1 - - [01/Nov/2023:18:54:00 +0000] "GET /realms/master/protocol/openid-connect/userinfo HTTP/1.1" 200 98 "-" "curl/7.68.0" "172.19.0.4:8080"
`
```

open the console Infinispan

```sh
# Observe active sessions
http://127.0.0.1:11222/console/cache/user-sessions admin/admin
```

try stop a 'keycloak' instance

```sh
# Observe stop and start of keycloak
# Open in new console
docker-compose logs -f keycloak

# Stop a one 'keycloak' instance
keycloak_1=$(docker ps -aqf "name=keycloak-1")
docker stop $keycloak_1

function getUser() {
   local amount=$1
   local pause=$2
   for ((i=1;i<=amount;i++))
   do
      curl -k -X GET http://127.0.0.1:8080/realms/master/protocol/openid-connect/userinfo \
         --noproxy '*' -H "Accept: application/json" \
         -H "Authorization: Bearer $TKN" | jq .
      
      [[ -n $pause ]] && echo -e "\e[32mWait ${pause}s for next request..\e[0m" && sleep $pause;
   done
}

# Recover a new Token in case the current one expired
export TKN=$(curl -k -X POST http://127.0.0.1:8080/realms/master/protocol/openid-connect/token \
    -H "Content-application: Type/x-www-form-urlencoded" --noproxy '*' \
    -d "username=admin" \
    -d 'password=admin' \
    -d 'grant_type=password' \
    -d 'client_id=admin-cli' \
    -d 'scope=openid' \
    | jq -r '.access_token')

# See session requests in different Keycloak instances
# Open in new console
docker-compose logs -f proxy

# Request information from a single keycloak instance
getUser 10

# Start the previously stopped instance
# And
# Request information from all keycloak instances
docker start $keycloak_1 && getUser 20 1
```

## TODO

1. Establish SSL communication between Keycloak and Infinispan
2. Test with more than 2 keycloak instances and more than one for Infinispan

## Links

* https://www.keycloak.org/server/caching
* https://github.com/infinispan-demos/quarkus-insights-demo
* https://github.com/keycloak/keycloak/issues/13926
* https://github.com/codecentric/helm-charts/blob/master/charts/keycloakx/examples/postgresql-kubeping/readme.md
* https://github.com/olivierboudet/keycloak-infinispan-jdbc
