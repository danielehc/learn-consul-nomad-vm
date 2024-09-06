# resource "consul_config_entry" "proxy_defaults" {
#   kind = "proxy-defaults"
#   # Note that only "global" is currently supported for proxy-defaults and that
#   # Consul will override this attribute if you set it to anything else.
#   name = "global"

#   config_json = jsonencode({
#     Config = {
#   		Protocol = "http"
# 		}
#   })
# }

# resource "consul_config_entry" "nginx_default_http" {
#   name = "nginx"
#   kind = "service-defaults"

#   config_json = jsonencode({
#   	"Namespace": "default",
#   	"Protocol": "http"
#   })
# }

# resource "consul_config_entry" "frontend_default_http" {
#   name = "frontend"
#   kind = "service-defaults"

#   config_json = jsonencode({
#   	"Namespace": "default",
#   	"Protocol": "http"
#   })
# }

resource "consul_config_entry" "database_default_tcp" {
  name = "database"
  kind = "service-defaults"

  config_json = jsonencode({
  	"Namespace": "default",
  	"Protocol": "tcp"
  })
}

resource "consul_config_entry" "nginx_default_http" {
  name = "nginx"
  kind = "service-defaults"

  config_json = jsonencode({
  	"Namespace": "default",
  	"Protocol": "http"
  })
}

# # resource "consul_config_entry_service_defaults" "default_http" {
# #   name = "*"
# #   namespace = "default"
# #   protocol = "http"
# # }


# # nomad namespace apply \
# #     -description "namespace for Consul API Gateways" \
# #     ingress

# resource "nomad_namespace" "ingress" {
#   name        = "ingress"
#   description = "Namespace for Consul API Gateways"
# }


# resource "consul_acl_auth_method" "nomad-workloads" {
#   name        = "nomad-workloads"
#   type        = "jwt"
#   description = "JWT auth method for Nomad services and workloads"

#   config_json = jsonencode({
#   	"JWKSURL": "https://127.0.0.1:4646/.well-known/jwks.json",
# 		"JWKSCACert" : "${tls_self_signed_cert.datacenter_ca.cert_pem}"
#   	"JWTSupportedAlgs": ["RS256"],
#   	"BoundAudiences": ["consul.io"],
#   	"ClaimMappings": {
#     	"nomad_namespace": "nomad_namespace",
#     	"nomad_job_id": "nomad_job_id",
#     	"nomad_task": "nomad_task",
#     	"nomad_service": "nomad_service"
#   	}
# 	})
# }

# # consul acl binding-rule create \
# #     -method 'nomad-workloads' \
# #     -description 'Nomad API gateway' \
# #     -bind-type 'templated-policy' \
# #     -bind-name 'builtin/api-gateway' \
# #     -bind-vars 'Name=${value.nomad_job_id}' \
# #     -selector '"nomad_service" not in value and value.nomad_namespace==ingress'

# resource "consul_acl_binding_rule" "test" {
#   auth_method = "nomad-workloads"
#   description = "Nomad API gateway"
#   bind_type   = "templated-policy"
#   bind_name   = "builtin/api-gateway"

#   selector    = "serviceaccount.namespace==default"
# }