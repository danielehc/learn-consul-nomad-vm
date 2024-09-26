# Cracking the monolith with Consul and Nomad

This repo covers how to set up a cluster running both Consul and Nomad and use it to deploy the HashiCups application.

There are several jobspec files for the application and each one builds on the previous, moving away from the monolithic design and towards microservices.


## Prerequisites

- [Nomad CLI](https://developer.hashicorp.com/nomad/install) installed
- [Consul CLI](https://developer.hashicorp.com/consul/install) installed
- [Packer CLI](https://developer.hashicorp.com/packer/install) installed
- [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) installed
- [AWS account](https://portal.aws.amazon.com/billing/signup?nc2=h_ct&src=default&redirect_url=https%3A%2F%2Faws.amazon.com%2Fregistration-confirmation#/start) with [credentials environment variables set](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-envvars.html)
- [`openssl`](https://openssl-library.org/source/index.html) and [`hey`](https://github.com/rakyll/hey) CLI tools installed


## Steps

1. [Build the cluster](#1-build-the-cluster)
1. [Set up Consul and Nomad access](#2-set-up-consul-and-nomad-access)
1. [Deploy the initial HashiCups application](#3-deploy-initial-hashicups-application)
1. [Deploy HashiCups with Consul service discovery and DNS](#4-deploy-hashicups-with-consul-service-discovery-and-dns)
1. [Deploy HashiCups with service mesh and API gateway](#5-deploy-hashicups-with-service-mesh-and-api-gateway)
1. [Scale the HashiCups application](#6-scale-the-hashicups-application)
1. [Cleanup jobs and infrastructure](#7-cleanup)

## 1. Build the cluster

Begin by creating the machine image with Packer.

### Update the variables file for Packer

Change into the `aws` directory.

```
cd aws
```

Rename `variables.hcl.example` to `variables.hcl` and open it in your text editor.

```
cp variables.hcl.example variables.hcl
```

Update the region variable with your preferred AWS region. In this example, the region is `us-east-1`. The remaining variables are for Terraform and you can update them after building the AMI.

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


Build the image and provide the variables file with the `-var-file` flag.

```
packer build -var-file=variables.hcl image.pkr.hcl
```

Example output from the above command.

```
Build 'amazon-ebs' finished after 14 minutes 32 seconds.

==> Wait completed after 14 minutes 32 seconds

==> Builds finished. The artifacts of successful builds are:
--> amazon-ebs: AMIs were created:
us-east-1: ami-0445eeea5e1406960
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

The Terraform code uses the Consul Terraform provider to create Consul ACL tokens.

Consul is configured with TLS encryption and to trust the certificate provided by the Consul servers. The Consul Terraform provider requires the `CONSUL_TLS_SERVER_NAME` environment variable to be set.

The Terraform code defaults the `datacenter` and `domain` variables in `variables.hcl` to `dc1` and `global` so `CONSUL_TLS_SERVER_NAME` will be `consul.dc1.global`.

You can update these variables with other values. If you do, be sure to also update the `CONSUL_TLS_SERVER_NAME` variable.


Export the `CONSUL_TLS_SERVER_NAME` environment variable.

```
export CONSUL_TLS_SERVER_NAME="consul.dc1.global"
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

From the Terraform output you can retrieve the links to connect to your newly created datacenter.

```
Apply complete! Resources: 85 added, 0 changed, 0 destroyed.

Outputs:

Configure-local-environment = "source ./datacenter.env"
Consul_UI = "https://52.202.91.53:8443"
Consul_UI_token = "8d964e70-9bfa-f410-9d6b-0e0ccf7292b4"
Nomad_UI = "https://52.202.91.53:4646"
Nomad_UI_token = <sensitive>
```

## 2. Set up Consul and Nomad access

Once Terraform finishes creating the infrastructure, you can set up access to Consul and Nomad from your local environment.

Run the `datacenter.env` script to set Consul and Nomad environment variables with values from the infrastructure Terraform created.

```
source ./datacenter.env
```

Open the Consul UI with the URL in the `Consul_UI` Terraform output variable and log in with the token in the `Consul_UI_token` output variable. You will need to trust the certificate in your browser.

Open the Nomad UI with the IP in `Nomad_UI` and log in with `Nomad_UI_token`.

Test connectivity to the Nomad cluster from your local environment.

```
nomad server members
```

## 3. Deploy initial HashiCups application

HashiCups represents a monolithic application that has been broken apart into separate services and configured to run with Docker Compose. The initial version is a translation of the fictional Docker Compose file to a Nomad jobspec.

Submit the initial jobspec to Nomad. Note that you must submit the job from the `aws` directory as the `NOMAD_CACERT` variable references the `certs` directory here.

```
nomad job run ../shared/jobs/01.hashicups.nomad.hcl
```

View the application by navigating to the public IP address of the NGINX service endpoint. Find the IP by first finding the node on which the service is running.

```
nomad job allocs hashicups
```

Example output from the above command.

```
ID        Node ID   Task Group  Version  Desired  Status   Created    Modified
e50ca6bd  7ff2205f  hashicups   0        run      running  1m22s ago  53s ago
```

Copy the `Node ID` value and use it in the `nomad node status -verbose [NODE_ID]` command to find the IP address. In this example, the ID is `7ff2205f`.

```
nomad node status -verbose 7ff2205f | grep -i public-ipv4
```

Example output from the above command.

```
unique.platform.aws.public-ipv4          = 18.191.53.222
```

Copy the IP address and open it in your browser. You do not need to specify a port as NGINX is running on port `80`.

Stop the deployment when you are ready to move on. The [`-purge` flag](https://developer.hashicorp.com/nomad/docs/commands/job/stop#purge) removes the job from the UI.

```
nomad job stop -purge hashicups
```

## 4. Deploy HashiCups with Consul service discovery on a single VM

This jobspec integrates Consul and uses service discovery and DNS to facilitate communication between the microservices but runs all of the services on a single node.

Submit the job to Nomad.

```
nomad job run ../shared/jobs/02.hashicups.nomad.hcl
```

Open the Consul UI and navigate to the **Services** page to see that each microservice is now registered in Consul with health checks.

Click on the **nginx** service and then click on the instance name to view the instance details page. Copy the public hostname in the top right corner of the page and open it in your browser to see the application.

Stop the deployment when you are ready to move on.

```
nomad job stop -purge hashicups
```

## 5. Deploy HashiCups with Consul service discovery on multiple VMs

This jobspec separates the services into their own task groups and allows them to run on different nodes.

Submit the job to Nomad.

```
nomad job run ../shared/jobs/03.hashicups.nomad.hcl
```

Open the Consul UI and navigate to the **Services** page to see that each microservice is now registered in Consul with health checks.

Click on the **nginx** service and then click on the instance name to view the instance details page. Copy the public hostname in the top right corner of the page and open it in your browser to see the application.

Open the Nomad UI and navigate to the **Topology** page from the left navigation to see that the NGINX service is running on a different node than the other services.

Stop the deployment when you are ready to move on.

```
nomad job stop -purge hashicups
```

## 6. Deploy HashiCups with service mesh and API gateway

This jobspec further integrates Consul by using service mesh and API gateway. Services use `localhost` and the Envoy proxy to enable mutual TLS and upstream service configurations for better security. The API gateway allows external access to the NGINX service.

Change to the `jobs` directory.

```
cd ../shared/jobs
```

Set up the API gateway configurations in Consul.

```
./04.api-gateway.config.sh
```

Set up the service intentions in Consul to allow the necessary services to communicate with each other.

```
./04.intentions.consul.sh
```

Change to the `aws` directory.

```
cd ../../aws
```

Submit the API gateway job to Nomad.

```
nomad job run ../shared/jobs/04.api-gateway.nomad.hcl
```

Submit the HashiCups job to Nomad.

```
nomad job run ../shared/jobs/04.hashicups.nomad.hcl
```

Open the Consul UI and navigate to the **Services** page to see that each microservice and the API gateway service are registered in Consul.

View the application by navigating to the public IP address of the API gateway. Find the IP by first finding the node on which the service is running. Note the `--namespace` flag; the API gateway is running in another namespace.

```
nomad job allocs --namespace=ingress api-gateway
```

Example output from the above command.

```
ID        Node ID   Task Group   Version  Desired  Status   Created     Modified
57e89ed2  e5af02d7  api-gateway  0        run      running  1m40s ago  57s ago
```

Copy the `Node ID` value and use it in the `nomad node status -verbose [NODE_ID]` command to find the IP address. In this example, the ID is `e5af02d7`.

```
nomad node status -verbose e5af02d7 | grep -i public-ipv4
```

Example output from the above command.

```
unique.platform.aws.public-ipv4          = 3.135.190.255
```

The API gateway is running over HTTPS and uses port `8443` so the URL will be `https://[IP_ADDRESS]:8443`. In this example, the URL is `https://3.135.190.255:8443`. You will need to trust the certificate in your browser.

Stop the deployment when you are ready to move on.

```
nomad job stop -purge hashicups
```

## 7. Scale the HashiCups application

This jobspec is the same as the API gateway version with the addition of the `scaling` block. This block instructs the Nomad Autoscaler to scale the frontend service up and down based on traffic load.

The Nomad Autoscaler is a separate service and is run here as a Nomad job.

### Set up the Nomad Autoscaler and submit the jobs

Change to the `jobs` directory.

```
cd ../shared/jobs
```

Run the autoscaler configuration script.

```
./05.autoscaler.config.sh 
```

Change back to the `aws` directory.

```
cd ../../aws
```

Submit the autoscaler job to Nomad.

```
nomad job run ../shared/jobs/05.autoscaler.nomad.hcl
```

Submit the HashiCups job to Nomad.

```
nomad job run ../shared/jobs/05.hashicups.nomad.hcl
```

### View the HashiCups application

View the application by navigating to the public IP address of the API gateway. Find the IP by first finding the node on which the service is running. Note the `--namespace` flag; the API gateway is running in another namespace.

```
nomad job allocs --namespace=ingress api-gateway
```

Example output from the above command.
```
ID        Node ID   Task Group   Version  Desired  Status   Created     Modified
57e89ed2  e5af02d7  api-gateway  0        run      running  1m40s ago  57s ago
```

Copy the `Node ID` value and use it in the `nomad node status -verbose [NODE_ID]` command to find the IP address. In this example, the ID is `e5af02d7`.

```
nomad node status -verbose e5af02d7 | grep -i public-ipv4
```

Example output from the above command.

```
unique.platform.aws.public-ipv4          = 3.135.190.255
```

The API gateway is running over HTTPS and uses port `8443` so the URL will be `https://[IP_ADDRESS]:8443`. In this example, the URL is `https://3.135.190.255:8443`. You will need to trust the certificate in your browser.

### Scale the frontend service

In another browser tab, open the Nomad UI, click on the **hashicups** job name, and then click on the **frontend** task from within the **Task Groups** list. This page displays a graph that shows scaling events at the bottom of the page. Keep this page open so you can reference it when scaling starts.

Open another terminal in your local environment to generate load with the [`hey`](https://github.com/rakyll/hey) tool.

Run the `hey` tool against the API gateway. In this example, the URL is `https://3.135.190.255:8443`. This command generates load for 20 seconds.

```
hey -z 20s -m GET https://3.135.190.255:8443
```

Navigate back to the **frontend** task group page in the Nomad UI and refresh it a few times to see that additional allocations are being created as the autoscaler scales the frontend service up and removed as the autoscaler scales it back down.

Open up the terminal session from where you submitted the jobs and stop the deployment when you are ready to move on.

```
nomad job stop -purge hashicups
```

## 8. Cleanup

### Clean up jobs

Stop and purge the hashicups and autoscaler jobs.

```
nomad job stop -purge hashicups autoscaler
```

Stop and purge the api-gateway job. Note that it runs in a different namespace.

```
nomad job stop -purge --namespace ingress api-gateway
```

### Destroy infrastructure

From within the `aws` directory, run the script to unset local environment variables.

```
source ../shared/scripts/unset_env_variables.sh
```

Use `terraform destroy` to remove the provisioned infrastructure. Respond `yes` to the prompt to confirm removal.

```
terraform destroy -var-file=variables.hcl
```

### Delete AMI and S3-store snapshots (optional)

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

## Reference

### HashiCups jobspec files and attributes

#### [01.hashicups.nomad.hcl](shared/jobs/01.hashicups.nomad.hcl)
- Initial jobspec for HashiCups
- Translation of fictional Docker Compose file to Nomad jobspec

#### [02.hashicups.nomad.hcl](shared/jobs/02.hashicups.nomad.hcl)
- Adds [`service` blocks](https://developer.hashicorp.com/nomad/docs/job-specification/service) with `provider="consul"` and [health checks](https://developer.hashicorp.com/nomad/docs/job-specification/check)
- Uses Consul DNS and static ports

#### [03.hashicups.nomad.hcl](shared/jobs/03.hashicups.nomad.hcl)
- Separates tasks into different groups
- Uses [client node constraints](https://developer.hashicorp.com/nomad/docs/job-specification/constraint)

#### [04.hashicups.nomad.hcl](shared/jobs/04.hashicups.nomad.hcl)
- Uses Consul service mesh
- Defines [service upstreams](https://developer.hashicorp.com/nomad/docs/job-specification/upstreams) and mapped service ports
- Uses `localhost` and [Envoy proxy](https://developer.hashicorp.com/consul/docs/connect/proxies/envoy) instead of DNS for service communication

#### [05.hashicups.nomad.hcl](shared/jobs/05.hashicups.nomad.hcl)
- Adds `scaling` block to the frontend service for [horizontal application autoscaling](https://developer.hashicorp.com/nomad/tools/autoscaling#horizontal-application-autoscaling)

### Other jobspec files

#### [04.api-gateway.nomad.hcl](shared/jobs/04.api-gateway.nomad.hcl)
- Runs the [API gateway](https://developer.hashicorp.com/consul/docs/connect/gateways/api-gateway) on port `8443`
- Constrains the job to a public client node

#### [05.autoscaler.nomad.hcl](shared/jobs/05.autoscaler.nomad.hcl)
- Runs the [Nomad Autoscaler agent](https://developer.hashicorp.com/nomad/tools/autoscaling/agent)
- Uses the [Nomad APM plugin](https://developer.hashicorp.com/nomad/tools/autoscaling/plugins/apm/nomad)