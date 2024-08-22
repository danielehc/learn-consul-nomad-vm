#-------------------------------------------------------------------------------
# Consul and Nomad Server(s)
#-------------------------------------------------------------------------------

resource "aws_instance" "server" {

  depends_on                  = [module.vpc]
  count                  = var.server_count

  ami                    = var.ami
  instance_type          = var.server_instance_type
  key_name               = aws_key_pair.vm_ssh_key-pair.key_name
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.consul_nomad_ui_ingress.id, 
    aws_security_group.ssh_ingress.id, 
    aws_security_group.allow_all_internal.id
  ]
  subnet_id = module.vpc.public_subnets[0]

  # instance tags
  # ConsulAutoJoin is necessary for nodes to automatically join the cluster
  tags = {
    Name = "${local.name}-server-${count.index}",
    ConsulJoinTag = "auto-join-${random_string.suffix.result}",
    NomadType = "server"
  }

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_block_device_size
    delete_on_termination = "true"
  }

  user_data = templatefile("${path.module}/../shared/data-scripts/user-data-server_new.sh", {
    server_count              = var.server_count
    region                    = var.region
    cloud_env                 = "aws"
    retry_join                = local.retry_join_consul
    nomad_binary              = var.nomad_binary
    nomad_consul_token_id     = random_uuid.nomad_id.result
    nomad_consul_token_secret = random_uuid.nomad_token.result
  })
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }
}