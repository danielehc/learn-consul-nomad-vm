job "autoscaler" {
  datacenters = ["dc1"]

  group "autoscaler" {
    count = 1

    network {
      dns {
      	servers = ["172.17.0.1"] 
      }
    }

    task "autoscaler" {
      driver = "docker"

      config {
        image   = "hashicorp/nomad-autoscaler:0.4.5"
        command = "nomad-autoscaler"
        args    = ["agent", "-config", "${NOMAD_TASK_DIR}/config.hcl"]
      }

      # TODO: Externalize nomad token
      template {
        data = <<EOF
plugin_dir = "/plugins"
log_level = "info"

nomad {
  address = "https://nomad.service.dc1.global:4646"
  token = "<NOMAD_TOKEN_VALUE>"
  skip_verify = true
}
apm "nomad" {
  driver = "nomad-apm"
}
          EOF

        destination = "${NOMAD_TASK_DIR}/config.hcl"
      }
    }
  }
}