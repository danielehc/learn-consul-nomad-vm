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

### Deploy the datacenter

Initialize the Terraform configuration to download the necessary providers and modules.

```
terraform init
```

Provision the resources and provide the variables file with the `-var-file` flag. Respond `yes` to the prompt to confirm the operation.

```
terraform apply -var-file=variables.hcl
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