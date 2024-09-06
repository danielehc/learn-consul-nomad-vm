variable "datacenters" {
  description = "A list of datacenters in the region which are eligible for task placement."
  type        = list(string)
  default     = ["*"]
}

variable "region" {
  description = "The region where the job should be placed."
  type        = string
  default     = "global"
}

job "pgadmin" {
  type   = "service"
  region = var.region
  datacenters = var.datacenters

  group "pgadmin" {

    count = 1

    network {
      mode = "bridge"
      port "pgadmin" {
        static = 8443
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }

    service {
      name = "pgadmin"
      provider = "consul"
      port = "pgadmin"
      address  = attr.unique.platform.aws.public-hostname

			connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "database"
              local_bind_port = 5432
            }
          }
        }
      }
		}

		task "pgadmin" {
			driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "="
        value     = "ingress"
      }
      
      meta {
        service = "pgadmin"
      }
      config {
        image = "dpage/pgadmin4:latest"
        ports = ["pgadmin"]
        # mount {
        #   type   = "bind"
        #   source = "local/default.conf"
        #   target = "/etc/nginx/conf.d/default.conf"
        # }
      }
			env {
        PGADMIN_DEFAULT_EMAIL       = "admin@pgadmin.io"
        PGADMIN_DEFAULT_PASSWORD     = "password"
				PGADMIN_LISTEN_PORT					= 8443
      }

		}
	}
}