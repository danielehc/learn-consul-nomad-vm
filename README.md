# Set up a Consul and Nomad cluster on the major cloud platforms

This repo is a companion to the [Cluster Setup](https://developer.hashicorp.com/nomad/tutorials/cluster-setup) collection of tutorials, containing configuration files to create a Nomad cluster with ACLs enabled on AWS, GCP, and Azure.

## Deploy steps

### Update the variables file for Packer

Rename `variables.hcl.example` to `variables.hcl` and open it in your text editor.

```
cp variables.hcl.example variables.hcl
```

Update the region variable with your preferred AWS region. In this example, the region is us-east-1. The remaining variables are for Terraform and you update them after building the AMI.

```yaml
# Packer variables (all are required)
region          = "us-east-1"

...
```

### Build the AMI

Initialize Packer to download the required plugins.

```
packer init image.pkr.hcl
```


Then, build the image and provide the variables file with the `-var-file` flag.

```
packer build -var-file=variables.hcl image.pkr.hcl
```

Example output

```
# ...

Build 'amazon-ebs' finished after 14 minutes 32 seconds.

==> Wait completed after 14 minutes 32 seconds

==> Builds finished. The artifacts of successful builds are:
--> amazon-ebs: AMIs were created:
us-east-1: ami-0445eeea5e1406960

Packer outputs the specific ami id once it finishes building the image. In this example, the value for the ami id would be ami-0445eeea5e1406960.
```

### Update the variables file for Terraform

Open `variables.hcl` in your text editor and update the `ami` variable with the value output from the Packer build. In this example, the value is `ami-0445eeea5e1406960`.

```yaml
# Packer variables (all are required)
region                    = "us-east-1"

# Terraform variables (all are required)
ami                       = "ami-0b2d23848882ae42d"
```

### Setup Consul server name

The Terraform code uses Consul Terraform provider to create Consul ACL tokens. 
Consul is configured with TLS encryption and to trust the certificate provided by the Consul servers the Consul Terraform provider requires the following environment variable to be set.

```
export CONSUL_TLS_SERVER_NAME="consul.dc1.global"
```

Change `dc1` and `global` with the values you set for `datacenter` and `domain` in `variables.hcl`.

### Deploy the datacenter

Initialize the Terraform configuration to download the necessary providers and modules.

```
terraform init
```

Provision the resources and provide the variables file with the `-var-file` flag. Respond `yes` to the prompt to confirm the operation.

```
terraform apply -var-file=variables.hcl
```

From the Terraform output you can retrieve the links to connect to your newly created datacenter.

```
Apply complete! Resources: 85 added, 0 changed, 0 destroyed.

Outputs:

Configure-local-environment = "source ./datacenter.env"
Consul_UI = "https://52.202.91.53:8443"
Consul_UI_token = "8d964e70-9bfa-f410-9d6b-0e0ccf7292b4"
IP_Addresses = <<EOT

Client public IPs: 3.83.145.4, 3.83.107.24, 3.95.182.36

Server public IPs: 52.202.91.53, 54.174.81.1, 3.83.84.52

The Consul UI can be accessed at https://52.202.91.53:8443
with the token: 8d964e70-9bfa-f410-9d6b-0e0ccf7292b4

EOT
Nomad_UI = "https://52.202.91.53:4646"
Nomad_UI_token = <sensitive>
```

## Cleanup steps

### Destroy infrastructure

Use `terraform destroy` to remove the provisioned infrastructure. Respond `yes` to the prompt to confirm removal.

```
terraform destroy -var-file=variables.hcl
```

### Delete AMI and S3-store snapshots

Delete the stored AMI built using packer using the `deregister-image` command. 

```
aws ec2 deregister-image --image-id ami-0445eeea5e1406960
```

To delete stored snapshots, first query for the snapshot using the `describe-snapshots` command.

```
aws ec2 describe-snapshots \
    --owner-ids self \
    --query "Snapshots[*].{ID:SnapshotId,Time:StartTime}"
```

Next, delete the stored snapshot using the `delete-snapshot` command by specifying the `snapshot-id` value.

```
aws ec2 delete-snapshot --snapshot-id snap-1234567890abcdef0
```