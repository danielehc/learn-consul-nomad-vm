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

# Begin Job Spec

job "hashicups" {
  type   = "service"
  region = var.region
  datacenters = var.datacenters

  # Constrain everything to a public client so nginx
  # is accessible on port 80
  constraint {
    attribute = "${meta.nodeRole}"
    operator  = "="
    value     = "ingress"
  }

  group "hashicups" {
    network {
      port "db" {
        static = 5432
      }
      port "product-api" {
        static = var.product_api_port
      }
      port "frontend" {
        static = var.frontend_port
      }
      port "payments-api" {
        static = var.payments_api_port
      }
      port "public-api" {
        static = var.public_api_port
      }
      port "nginx" {
        static = var.nginx_port
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    task "db" {
      driver = "docker"
      service {
        name = "database"
        provider = "consul"
        port = "db"
        # Update to something like attr.unique.network.ip-address if
        # running on local nomad cluster (agent -dev)
        address  = attr.unique.platform.aws.local-ipv4
      }
      meta {
        service = "database"
      }
      config {
        image   = "hashicorpdemoapp/product-api-db:${var.product_api_db_version}"
        ports = ["db"]
      }
      env {
        POSTGRES_DB       = "products"
        POSTGRES_USER     = "postgres"
        POSTGRES_PASSWORD = "password"
      }
    }
    task "product-api" {
      driver = "docker"
      service {
        name = "product-api"
        provider = "consul"
        port = "product-api"
        address  = attr.unique.platform.aws.local-ipv4
      }
      meta {
        service = "product-api"
      }
      config {
        image   = "hashicorpdemoapp/product-api:${var.product_api_version}"
        ports = ["product-api"]
      }
      template {
        data        = <<EOH
DB_CONNECTION="host=database.service.dc1.global port=5432 user=${var.postgres_user} password=${var.postgres_password} dbname=${var.postgres_db} sslmode=disable"
BIND_ADDRESS = "{{ env "NOMAD_IP_product-api" }}:${var.product_api_port}"
EOH
        destination = "local/env.txt"
        env         = true
      }
    }
    task "frontend" {
      driver = "docker"
      service {
        name = "frontend"
        provider = "consul"
        port = "frontend"
        address  = attr.unique.platform.aws.local-ipv4
      }
      meta {
        service = "frontend"
      }
      template {
        data        = <<EOH
# NEXT_PUBLIC_PUBLIC_API_URL="http://public-api.service.dc1.global:${var.public_api_port}"
NEXT_PUBLIC_PUBLIC_API_URL="/"
NEXT_PUBLIC_FOOTER_FLAG="whatever-string"
PORT="${var.frontend_port}"
EOH
        destination = "local/env.txt"
        env         = true
      }
      config {
        image   = "hashicorpdemoapp/frontend:${var.frontend_version}"
        ports = ["frontend"]
      }
    }
    task "payments-api" {
      driver = "docker"
      service {
        name = "payments-api"
        provider = "consul"
        port = "payments-api"
        address  = attr.unique.platform.aws.local-ipv4
      }
      meta {
        service = "payments-api"
      }
      config {
        image   = "hashicorpdemoapp/payments:${var.payments_version}"
        ports = ["payments-api"]
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
    task "public-api" {
      driver = "docker"
      service {
        name = "public-api"
        provider = "consul"
        port = "public-api"
        address  = attr.unique.platform.aws.local-ipv4
      }
      meta {
        service = "public-api"
      }
      config {
        image   = "hashicorpdemoapp/public-api:${var.public_api_version}"
        ports = ["public-api"] 
      }
      template {
        data        = <<EOH
BIND_ADDRESS = ":${var.public_api_port}"
PRODUCT_API_URI = "http://product-api.service.dc1.global:${var.product_api_port}"
PAYMENT_API_URI = "http://payments-api.service.dc1.global:${var.payments_api_port}"
EOH
        destination = "local/env.txt"
        env         = true
      }
    }
    task "nginx" {
      driver = "docker"
      service {
        name = "nginx"
        provider = "consul"
        port = "nginx"
        address  = attr.unique.platform.aws.public-hostname
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
    server frontend.service.dc1.global:${var.frontend_port};
}
server {
  listen {{ env "NOMAD_PORT_nginx" }};
  # server_name public-api.service.dc1.global;
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
  
  #  location /_next/static {
  #   proxy_cache STATIC;
  #   proxy_pass http://frontend_upstream;
  #   # For testing cache - remove before deploying to production
  #   add_header X-Cache-Status $upstream_cache_status;
  # }
  # location /static {
  #   proxy_cache STATIC;
  #   proxy_ignore_headers Cache-Control;
  #   proxy_cache_valid 60m;
  #   proxy_pass http://frontend_upstream;
  #   # For testing cache - remove before deploying to production
  #   add_header X-Cache-Status $upstream_cache_status;
  # }
  location / {
    # add_header 'Access-Control-Allow-Origin' '*' always;
		# add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
    # add_header 'Access-Control-Allow-Credentials' 'true' always;
		# add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,Keep-Alive,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;  
    proxy_pass http://frontend_upstream;
  }
  location /api {
    # add_header 'Access-Control-Allow-Origin' '*' always;
		# add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
    # add_header 'Access-Control-Allow-Credentials' 'true' always;
		# add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,Keep-Alive,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;  
    proxy_pass http://public-api.service.dc1.global:${var.public_api_port};
  }
}
        EOF
        destination = "local/default.conf"
      }
    }
  }
}