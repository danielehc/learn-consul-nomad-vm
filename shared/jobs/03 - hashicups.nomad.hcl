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
    network {
      port "db" {
        static = var.db_port
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    task "db" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
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
  }
  group "product-api" {
    network {
      port "product-api" {
        static = var.product_api_port
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    task "product-api" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
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
DB_CONNECTION="host=database.service.dc1.global port=${var.db_port} user=${var.postgres_user} password=${var.postgres_password} dbname=${var.postgres_db} sslmode=disable"
BIND_ADDRESS = "{{ env "NOMAD_IP_product-api" }}:${var.product_api_port}"
EOH
        destination = "local/env.txt"
        env         = true
      }
    }
  }
  group "frontend" {
    network {
      port "frontend" {
        static = var.frontend_port
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    task "frontend" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
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
NEXT_PUBLIC_FOOTER_FLAG="footer-string"
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
  }
  group "payments" {
    network {
      port "payments-api" {
        static = var.payments_api_port
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    task "payments-api" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
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
  }
  group "public-api" {
    network {
      port "public-api" {
        static = var.public_api_port
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    task "public-api" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "!="
        value     = "ingress"
      }
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
  }
  group "nginx" {
    network {
      port "nginx" {
        static = var.nginx_port
      }
      dns {
      	servers = ["172.17.0.1"] 
      }
    }
    task "nginx" {
      driver = "docker"
      constraint {
        attribute = "${meta.nodeRole}"
        operator  = "="
        value     = "ingress"
      }
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
  listen ${var.nginx_port};
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
  location / {
    proxy_pass http://frontend_upstream;
  }
  location /api {
    proxy_pass http://public-api.service.dc1.global:${var.public_api_port};
  }
}
        EOF
        destination = "local/default.conf"
      }
    }
  }
}