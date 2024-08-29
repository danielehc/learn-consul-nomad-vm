resource "consul_config_entry" "proxy_defaults" {
  kind = "proxy-defaults"
  # Note that only "global" is currently supported for proxy-defaults and that
  # Consul will override this attribute if you set it to anything else.
  name = "global"

  config_json = jsonencode({
    Config = {
  		Protocol = "http"
		}
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

resource "consul_config_entry" "frontend_default_http" {
  name = "frontend"
  kind = "service-defaults"

  config_json = jsonencode({
  	"Namespace": "default",
  	"Protocol": "http"
  })
}

# resource "consul_config_entry_service_defaults" "default_http" {
#   name = "*"
#   namespace = "default"
#   protocol = "http"
# }