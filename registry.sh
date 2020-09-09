#!/bin/bash

openssl req -newkey rsa:4096 -nodes -sha256 -keyout domain.key -x509 -days 365 -out domain.crt
htpasswd -bBc /opt/registry/auth/htpasswd admin pass

podman run -d --name mirror-registry \
    -p 5000:5000 --restart=always \
    -v /opt/registry/data:/var/lib/registry:z \
    -v /opt/registry/auth:/auth:z \
    -v /opt/registry/certs:/certs:z \
    -e "REGISTRY_AUTH=htpasswd" \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
    -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
    docker.io/library/registry:2

sudo cp /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors
sudo update-ca-trust

#create auth file
podman login --authfile ~/.podauth -u admin -p pass myregistry:5000
