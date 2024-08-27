# Exports all needed environment variables to connect to Consul and Nomad 
# datacenter using CLI commands
resource "local_file" "environment_variables" {
  filename = "datacenter.env"
  content = <<-EOT
    export CONSUL_HTTP_ADDR="https://${aws_instance.server[0].public_ip}:8443"
    export CONSUL_HTTP_TOKEN="${random_uuid.consul_mgmt_token.result}"
    export CONSUL_HTTP_SSL="true"
    export CONSUL_CACERT="./certs/datacenter_ca.cert"
    export CONSUL_TLS_SERVER_NAME="consul.${var.datacenter}.${var.domain}"
    export NOMAD_ADDR="https://${aws_instance.server[0].public_ip}:4646"
    export NOMAD_TOKEN="${random_uuid.nomad_mgmt_token.result}"
    export NOMAD_CACERT="./certs/datacenter_ca.cert"
    export NOMAD_TLS_SERVER_NAME="nomad.${var.datacenter}.${var.domain}"
  EOT
}

output "Configure-local-environment" {
  value = "source ./datacenter.env"
}

output "Consul_UI" {
  value = "https://${aws_instance.server[0].public_ip}:8443"
}

output "Nomad_UI" {
  value = "https://${aws_instance.server[0].public_ip}:4646"
}

output "Nomad_UI_token" {
  value = nomad_acl_token.nomad-user-token.secret_id
  sensitive = true
}
################################################################################
################################################################################

# output "lb_address_consul_nomad" {
#   value = "http://${aws_instance.server[0].public_ip}"
# }

output "Consul_UI_token" {
  value = random_uuid.consul_mgmt_token.result
}

output "IP_Addresses" {
  value = <<CONFIGURATION

Client public IPs: ${join(", ", aws_instance.client[*].public_ip)}

Server public IPs: ${join(", ", aws_instance.server[*].public_ip)}

The Consul UI can be accessed at https://${aws_instance.server[0].public_ip}:8443
with the token: ${random_uuid.consul_mgmt_token.result}
CONFIGURATION
}
