#!/usr/bin/env bash

source ../../aws/datacenter.env

export CONSUL_CACERT="../../aws/certs/datacenter_ca.cert"
export NOMAD_CACERT="../../aws/certs/datacenter_ca.cert"

_consul_addr=`echo ${CONSUL_HTTP_ADDR} | sed 's/^.*\:\/\///g'`

_CERT_CONTENT="$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ${CONSUL_CACERT})"

_JWT_FILE="/tmp/consul-auth-method-nomad-workloads.json"
_BR_FILE="/tmp/consul-binding-rule-nomad-workloads.json"

tee ${_JWT_FILE} > /dev/null << EOF
{
  "JWKSURL": "https://127.0.0.1:4646/.well-known/jwks.json",
  "JWKSCACert" : "`echo ${_CERT_CONTENT}`",
  "JWTSupportedAlgs": ["RS256"],
  "BoundAudiences": ["consul.io"],
  "ClaimMappings": {
    "nomad_namespace": "nomad_namespace",
    "nomad_job_id": "nomad_job_id",
    "nomad_task": "nomad_task",
    "nomad_service": "nomad_service"
  }
}
EOF

# cat ${_JWT_FILE} 

cat ${_JWT_FILE} | jq

# This auth method creates an endpoint for generating Consul ACL tokens from Nomad workload identities.

consul acl auth-method create \
            -name 'nomad-workloads' \
            -type 'jwt' \
            -description 'JWT auth method for Nomad services and workloads' \
            -config "@${_JWT_FILE}"


# consul acl auth-method list

nomad namespace apply \
    -description "namespace for Consul API Gateways" \
    ingress

# consul acl binding-rule create \
#     -method 'nomad-workloads' \
#     -description 'Nomad API gateway' \
#     -bind-type 'templated-policy' \
#     -bind-name 'builtin/api-gateway' \
#     -bind-vars 'Name=${value.nomad_job_id}' \
#     -selector '"nomad_service" not in value and value.nomad_namespace==ingress'

var='${value.nomad_job_id}'

tee ${_BR_FILE} > /dev/null << EOF
{
  "AuthMethod": "nomad-workloads",
  "Description": "Nomad API gateway",
  "BindType": "templated-policy",
  "BindName": "builtin/api-gateway",
  "BindVars": {
    "Name": "${var}"
  },
  "Selector": "\"nomad_service\" not in value and value.nomad_namespace==ingress"
}
EOF

# cat ${_BR_FILE}

# cat ${_BR_FILE} | jq

# esxit 0

for i in `consul acl binding-rule list -format json | jq -r .[].ID`; do
  consul acl binding-rule delete -id=$i
done


curl --silent \
  --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --connect-to ${CONSUL_TLS_SERVER_NAME}:8443:${_consul_addr} \
  --cacert ${CONSUL_CACERT} \
  --data @${_BR_FILE} \
  --request PUT \
  https://${CONSUL_TLS_SERVER_NAME}:8443/v1/acl/binding-rule

consul acl binding-rule list -format json


_GW_config_FILE="/tmp/config-gateway-api.hcl"

tee ${_GW_config_FILE} > /dev/null << EOF
Kind = "api-gateway"
Name = "gateway-api"

// Each listener configures a port which can be used to access the Consul cluster
Listeners = [
    {
        Port = 8443
        Name = "api-gw-listener"
        Protocol = "http"
        TLS = {
            Certificates = [
                {
                    Kind = "inline-certificate"
                    Name = "api-gw-certificate"
                }
            ]
        }
    }
]
EOF

export COMMON_NAME="hashicups.hashicorp.com"

_ssl_conf_FILE="/tmp/gateway-api-ca-config.cnf"

tee ${_ssl_conf_FILE} > /dev/null << EOF
[req]
default_bit = 4096
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
countryName             = US
stateOrProvinceName     = California
localityName            = San Francisco
organizationName        = HashiCorp
commonName              = ${COMMON_NAME}
EOF


_ssl_key_file="/tmp/gateway-api-cert.key"
_ssl_csr_file="/tmp/gateway-api-cert.csr"
_ssl_crt_file="/tmp/gateway-api-cert.csr"

openssl genrsa -out ${_ssl_key_file}  4096 2>/dev/null

openssl req -new \
  -key ${_ssl_key_file} \
  -out ${_ssl_csr_file} \
  -config ${_ssl_conf_FILE} 2>/dev/null

openssl x509 -req -days 3650 \
  -in ${_ssl_csr_file} \
  -signkey ${_ssl_key_file} \
  -out ${_ssl_crt_file} 2>/dev/null

export API_GW_KEY=`cat ${_ssl_key_file}`
export API_GW_CERT=`cat ${_ssl_crt_file}`


_GW_certificate_FILE="/tmp/config-gateway-api-certificate.hcl"

tee ${_GW_certificate_FILE} > /dev/null << EOF
Kind = "inline-certificate"
Name = "api-gw-certificate"

Certificate = <<EOT
${API_GW_CERT}
EOT

PrivateKey = <<EOT
${API_GW_KEY}
EOT
EOF

consul config write ${_GW_config_FILE}
consul config write ${_GW_certificate_FILE}

