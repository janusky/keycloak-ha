# keycloak-ha

Ejecución de [Keycloak](https://quay.io/repository/keycloak/keycloak) en modo alta disponibilidad utilizando [cache distribuida](https://www.keycloak.org/server/caching) con instancia de [Infinispan](https://infinispan.org/) y un [Nginx](https://nginx.org/) como balanceador de carga.

* Inspirado en https://github.com/olivierboudet/keycloak-infinispan-jdbc

**CONTENIDO**

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

Contar con más de una instancia de Keycloak y ambas compartan las sesiones establecidas en cualquiera de las instancias.  
Monitorear las sesiones creadas en la instancia de Infinispan.

## Run

>NOTA
>Ejecutar infinispan y postgres para luego crear usuario de acceso a infinispan.

```sh
# Se inicia postgres y infinispan
docker-compose up -d postgres infinispan

# Creación de usuario de acceso a infinispan
# docker exec $(docker ps -aqf "ancestor=quay.io/infinispan/server:14.0.19.Final") sh -c './bin/cli.sh user create admin -p admin -g admin'
./infinispan_user.sh admin admin
`
http://127.0.0.1:11222/ - Open the console -> admin/admin
`
# Ejecutar dos instancias de keycloak
docker-compose up -d --scale keycloak=2

# Logs all: docker-compose logs -f
docker-compose logs -f infinispan
docker-compose logs -f keycloak
docker-compose logs -f nginx
```

## Test

Se crea un token de acceso y luego se solicita la información en sesión del usuario con el token provisto.

Puede optar por realizar las pruebas en la consola observando cada instrucción ejecutada o invocar la ejecución de un script bash.

* [Test Console](#test-console)
* [Test Script Bash](#test-script-bash)

### Test Script Bash

En el archivo [test.sh](test.sh) se codificó un script bash para realizar una serie de pruebas similar a las de [Test Console](#test-console).

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
# Ejecutar log para ver las peticiones de sesión a diferentes instancias de Keycloak
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
# Observar las sesiones activas
http://127.0.0.1:11222/console/cache/user-sessions admin/admin
```

try stop a 'keycloak' instance

```sh
# Ejecutar logs si desea observar stop y start de keycloak
# Open in new console
docker-compose logs -f keycloak

# Detener una instancia de keycloak
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

# Recuperar un nuevo Token por si expiró el actual
export TKN=$(curl -k -X POST http://127.0.0.1:8080/realms/master/protocol/openid-connect/token \
    -H "Content-application: Type/x-www-form-urlencoded" --noproxy '*' \
    -d "username=admin" \
    -d 'password=admin' \
    -d 'grant_type=password' \
    -d 'client_id=admin-cli' \
    -d 'scope=openid' \
    | jq -r '.access_token')

# Log para observar las peticiones sesión a las instancias de keycloak
# Open in new console
docker-compose logs -f nginx

# Pedir info a una sola instancia de keycloak
getUser 10

# Iniciar la instancia antes detenida
# Pedir info a una sola instancia de keycloak
docker start $keycloak_1 && getUser 20 1
```

## TODO

1. Establecer comunicación SSL entre Keycloak y Infinispan
2. Hacer pruebas con más de 2 instancias de keycloak y más de una para Infinispan

## Links

* https://www.keycloak.org/server/caching
* https://github.com/infinispan-demos/quarkus-insights-demo
* https://github.com/keycloak/keycloak/issues/13926
* https://github.com/codecentric/helm-charts/blob/master/charts/keycloakx/examples/postgresql-kubeping/readme.md
* https://github.com/olivierboudet/keycloak-infinispan-jdbc
