#-------------------------------------------------------------------------------
# Consul and Nomad Client(s)
#-------------------------------------------------------------------------------

resource "aws_instance" "client" {
  
  depends_on             = [aws_instance.server]
  count                  = var.client_count
  
  ami                    = var.ami
  instance_type          = var.client_instance_type
  key_name               = aws_key_pair.vm_ssh_key-pair.key_name
  vpc_security_group_ids = [
    # aws_security_group.consul_nomad_ui_ingress.id, 
    aws_security_group.ssh_ingress.id, 
    aws_security_group.clients_ingress.id, 
    aws_security_group.allow_all_internal.id
  ]
  subnet_id = module.vpc.public_subnets[0]

  # instance tags
  # ConsulAutoJoin is necessary for nodes to automatically join the cluster
  tags = {
    Name = "${local.name}-client-${count.index}",
    ConsulJoinTag = "auto-join-${random_string.suffix.result}",
    NomadType = "client"
  } 

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_block_device_size
    delete_on_termination = "true"
  }

  ebs_block_device {
    device_name           = "/dev/xvdd"
    volume_type           = "gp2"
    volume_size           = "50"
    delete_on_termination = "true"
  }

  user_data = templatefile("${path.module}/../shared/data-scripts/user-data-client_new.sh", {
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