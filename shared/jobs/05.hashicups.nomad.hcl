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

variable "frontend_version" {
  description = "Docker version tag"
  default = "v1.0.9"
}

variable "public_api_version" {
  description = "Docker version tag"
  default = "v0.0.7"
}

variable "payments_version" {
  description = "Docker version tag"
  default = "v0.0.16"
}

variable "product_api_version" {
  description = "Docker version tag"
  default = "v0.0.22"
}

variable "product_api_db_version" {
  description = "Docker version tag"
  default = "v0.0.22"
}

variable "postgres_db" {
  description = "Postgres DB name"
  default = "products"
}

variable "postgres_user" {
  description = "Postgres DB User"
  default = "postgres"
}

variable "postgres_password" {
  description = "Postgres DB Password"
  default = "password"
}

variable "product_api_port" {
  description = "Product API Port"
  default = 9090
}

variable "frontend_port" {
  description = "Frontend Port"
  default = 3000
}

variable "payments_api_port" {
  description = "Payments API Port"
  default = 8080
}

variable "public_api_port" {
  description = "Public API Port"
  default = 8081
}

variable "nginx_port" {
  description = "Nginx Port"
  default = 80
}

variable "db_port" {
  description = "Postgres Database Port"
  default = 5432
}

# Begin Job Spec

job "hashicups" {
  type   = "service"
  region = var.region
  datacenters = var.datacenters

  group "db" {

    count = 1

    network {
      mode = "bridge"
      # port "db" {
      #   static = var.db_port
      # }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    
    service {
      name = "database"
      provider = "consul"
      # port = "db"
      port = "${var.db_port}"
      # Update to something like attr.unique.network.ip-address if
      # running on local nomad cluster (agent -dev)
      # address  = attr.unique.platform.aws.local-ipv4
      
      connect {
        sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
            }
          }
        }
      }
      
      check {
        name      = "Database ready"
        type      = "script"
        command   = "/usr/bin/pg_isready"
        args      = ["-d", "${var.db_port}"]
        interval  = "5s"
        timeout   = "2s"
        on_update = "ignore_warnings"
        task      = "db"
      }
    }
    
    
    task "db" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
      
      meta {
        service = "database"
      }
      config {
        image   = "hashicorpdemoapp/product-api-db:${var.product_api_db_version}"
        ports = ["${var.db_port}"]
      }
      env {
        POSTGRES_DB       = "products"
        POSTGRES_USER     = "postgres"
        POSTGRES_PASSWORD = "password"
      }
    }
  }

  group "product-api" {

    count = 1

    network {
      mode = "bridge"
      # port "product-api" {
      #   static = var.product_api_port
      # }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    
    service {
        name = "product-api"
        provider = "consul"
        # port = "product-api"
        port = "${var.product_api_port}"
        # address  = attr.unique.platform.aws.local-ipv4

        connect {
            sidecar_service {
              proxy {
                transparent_proxy {
                  no_dns = true
                }
              }
            }
        }


        # DB connectivity check 
      check {
        name        = "DB connection ready"
        address_mode = "alloc"
        type      = "http" 
        path      = "/health/readyz"
        interval  = "5s"
        timeout   = "5s"
        expose    = true
      }

      # Server ready check
      check {
        name        = "Product API ready"
        address_mode = "alloc"
        type      = "http" 
        path      = "/health/livez" 
        interval  = "5s"
        timeout   = "5s"
        expose    = true
      }
    }
    
    task "product-api" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
      
      meta {
        service = "product-api"
      }
      config {
        image   = "hashicorpdemoapp/product-api:${var.product_api_version}"
        ports = ["${var.product_api_port}"]
      }
      template {
        data        = <<EOH
DB_CONNECTION="host=database.virtual.global port=${var.db_port} user=${var.postgres_user} password=${var.postgres_password} dbname=${var.postgres_db} sslmode=disable"
BIND_ADDRESS = "{{ env "NOMAD_IP_product-api" }}:${var.product_api_port}"
EOH
        destination = "local/env.txt"
        env         = true
      }
    }
  }
  group "frontend" {
    
    count = 1

    network {
      mode = "bridge"
      # port "frontend" {
      #   static = var.frontend_port
      # }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    
    service {
      name = "frontend"
      provider = "consul"
      # port = "frontend"
      port = "${var.frontend_port}"
      # address  = attr.unique.platform.aws.local-ipv4

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
            }
          }
        }
      }

        check {
          name      = "Frontend ready"
          address_mode = "alloc"
					type      = "http"
          path      = "/"
				  interval  = "5s"
					timeout   = "5s"
          expose    = true
        }

    }
    
    task "frontend" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
      
      meta {
        service = "frontend"
      }

      template {
        data        = <<EOH
NEXT_PUBLIC_PUBLIC_API_URL="/"
NEXT_PUBLIC_FOOTER_FLAG="HashiCups Frontend instance {{ env "NOMAD_ALLOC_INDEX" }}"
PORT="${var.frontend_port}"
EOH
        destination = "local/env.txt"
        env         = true
      }
      config {
        image   = "hashicorpdemoapp/frontend:${var.frontend_version}"
        ports = ["${var.frontend_port}"]
      }
    }
  }

  group "payments" {

    count = 1

    network {
      mode = "bridge"
      # port "payments-api" {
      #   static = var.payments_api_port
      # }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }

    service {
      name = "payments-api"
      provider = "consul"
      #port = "payments-api"
      port = "${var.payments_api_port}"
      # address  = attr.unique.platform.aws.local-ipv4

      connect {
        sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
            }
          }
        }
      }

      check {
        name      = "Payments API ready"
        address_mode = "alloc"
        type      = "http"
        path			= "/actuator/health"
        interval  = "5s"
        timeout   = "5s"
        expose    = true
      }
    }

    task "payments-api" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
      
      meta {
        service = "payments-api"
      }

      config {
        image   = "hashicorpdemoapp/payments:${var.payments_version}"
        ports = ["${var.payments_api_port}"]
        mount {
          type   = "bind"
          source = "local/application.properties"
          target = "/application.properties"
        }
      }
      template {
        data = "server.port=${var.payments_api_port}"
        destination = "local/application.properties"
      }
      resources {
        memory = 500
      }
    }
  }

  group "public-api" {

    count = 1

    network {
      mode = "bridge"
      # port "public-api" {
      #   static = var.public_api_port
      # }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    
    service {
        name = "public-api"
        provider = "consul"
        # port = "public-api"
        port = "${var.public_api_port}"
      # address  = attr.unique.platform.aws.local-ipv4

        connect {
            sidecar_service {
            proxy {
              transparent_proxy {
                no_dns = true
              }
            }
          }
        }

      check {
        name      = "Public API ready"
        address_mode = "alloc"
        type      = "http"
        path			= "/health"
        interval  = "5s"
        timeout   = "5s"
        expose    = true
      }
    }
    task "public-api" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
      
      meta {
        service = "public-api"
      }
      config {
        image   = "hashicorpdemoapp/public-api:${var.public_api_version}"
        ports = ["${var.public_api_port}"] 
      }
      template {
        data        = <<EOH
BIND_ADDRESS = ":${var.public_api_port}"
PRODUCT_API_URI = "http://product-api.virtual.global:${var.product_api_port}"
PAYMENT_API_URI = "http://payments-api.virtual.global:${var.payments_api_port}"
EOH
        destination = "local/env.txt"
        env         = true
      }
    }
  }

  group "nginx" {

    count = 1

    network {
      mode = "bridge"
      port "nginx" {
        static = var.nginx_port
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }

    service {
      name = "nginx"
      provider = "consul"
      port = "nginx"
      address  = attr.unique.platform.aws.public-hostname

      connect {
          sidecar_service {
          proxy {
            transparent_proxy {
              no_dns = true
            }
          }
        }
      }

      check {
        name      = "NGINX ready"
        type      = "http"
        path			= "/health"
        interval  = "5s"
        timeout   = "5s"
        expose    = true
      }
    }

    task "nginx" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "="
        value     = "ingress"
      }
      
      meta {
        service = "nginx-reverse-proxy"
      }
      config {
        image = "nginx:alpine"
        ports = ["nginx"]
        mount {
          type   = "bind"
          source = "local/default.conf"
          target = "/etc/nginx/conf.d/default.conf"
        }
      }
      template {
        data =  <<EOF
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=STATIC:10m inactive=7d use_temp_path=off;
upstream frontend_upstream {
    server frontend.virtual.global:${var.frontend_port};
}
server {
  listen ${var.nginx_port};
  server_name {{ env "NOMAD_IP_nginx" }};
  server_tokens off;
  gzip on;
  gzip_proxied any;
  gzip_comp_level 4;
  gzip_types text/css application/javascript image/svg+xml;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection 'upgrade';
  proxy_set_header Host $host;
  proxy_cache_bypass $http_upgrade;
  location = /health {
    access_log off;
    add_header 'Content-Type' 'application/json';
    return 200 '{"status":"UP"}';
  }
  location / {
    proxy_pass http://frontend_upstream;
  }
  location /api {
    proxy_pass http://public-api.virtual.global:${var.public_api_port};
  }
}
        EOF
        destination = "local/default.conf"
      }
    }
  }
}