# WebServer — EC2, ALB, EFS, S3 and CloudFront provisioned using Terraform + GitHub

Task: Have to launch web server on AWS EC2 with ALB.

1. Create a Key Pair and security group which allow the port 80, 22 and ICMP protocol for ingress.
2. Launch multiple EC2 instances.
3. In the created EC2 instances, use the key and security group which we have created in step 1.
4. Launch Elastic File System (EFS) and mount that volume into `/var/www/html` on all the instances.
5. Create an S3 bucket, and copy/deploy the image into it, and change permission to public readable.
6. Create a Cloudfront using S3 bucket (which contains image) and use the Cloudfront URL to update in code in `/var/www/html`.
7. Create a Load Balancer for EC2 instances.

## provider-variables-data

`provider` is used for telling Terraform as to which infrastructure/service provider will it be connecting to like in my use case, it will be an Iaas i.e. AWS. It is responsible for understanding API interactions and exposing resources.

To keep my credentials secure, I configured a profile with the required credentials and default region using AWS CLI and will be using it here. The profile can be configured with the following command.

```bash
aws configure --profile <profilename>
```

You can get your credentials from AWS Dashboard under the My Security Credentials.

Data sources allow data to be fetched or computed for use elsewhere in Terraform configuration. Use of data sources allows a Terraform configuration to make use of information defined outside of Terraform, or defined by another separate Terraform configuration.

I have used it to get the details of default and existing resources in my AWS. We will get the default VPC, live availability zones and the subnet ids in the selected VPC. This will be used later while creating other resources.

## rsa-keypair

`tls_private_key` is used to generate RSA encrypted private and public key-pair and also encodes it as PEM.

Using `local_file`, we will save the private key generated by tls_private_key on our host system to be used later as if we require to connect to our instance via SSH.

`aws_key_pair` will create a Key Pair in the AWS account using the public key generated previously. This key will be bound to EC2 instances for SSH connections.

## ec2

We will create a security group for the EC2 instances in the default VPC using its ID which we got from the data source.

Ingress is the incoming traffic to the instance. So will allow the following ports for it:

- 80: To allow HTTP traffic so users can hit the webserver and open the pages.
- 22: To allow secure remote connection to be made to the instance for the developers so that installations and updates can be done on the system.
- ICMP ports: All ICMP ports are open to check for ping connectivity.

Egress is the outgoing traffic from the instance. It will allow the instance to connect to anywhere on the internet or to anything on an internal network like EFS.

Next, we will be launching two EC2 instances. Both are based on RHEL8 image and are of type t2.micro. These will install in the default VPC. As subnet and availability zones are optional, I skipped them. Also, I attached a root block device for storage which is ephemeral as it will be deleted on instance termination.

We will then connect to the instances via SSH and use remote-exec provisioner to set up the required environment which will include installation of git, httpd and PHP. These steps can be made platform independent with the use of automation scripts like Ansible.

NOTE — You can also create multiple instances of the same type and with the same environment using the `count` keyword.

## efs

First, we will create a security group for the Elastic File System (EFS) wherein egress is open to everywhere and on every port but the ingress is open from the security group of WebServer EC2 instances on all ports as a measure of securing the EFS.

Next, we will create an aws_efs_file_system with a creation token(optional) which can be used as a reference if required. This will generate an Elastic File System.

`aws_efs_mount_target` will provide the mount targets for the File System which according to our code will be created in all available subnet ids in the default VPC as taken from data sources. We will also attach our previously created security group to each mount target.

`aws_efs_access_point` will provide an access point for the File System which be used later to mount the EFS in instances.

`null_resource` has been used to call in remote-exec provisioner to the instances to persistent mount the EFS on them in the required directory i.e. /var/www/html. The reference steps are available at (https://docs.aws.amazon.com/efs/latest/ug/installing-other-distro.html and https://docs.aws.amazon.com/efs/latest/ug/mount-fs-auto-mount-onreboot.html).

The files inside the EFS can be controlled from anywhere and in my case, I have chosen it to be done from one of the instances I have created. The GitHub repository with webpages will be cloned in /var/www/html and permissions will be changed accordingly. Also, SELinux is switched off for now (not recommended) so we don’t get Permission denied error on webpage.

## load-balancer

We will be betting up an Application Load Balancer (ALB) rather than the Classic Load Balancer.

So to begin with, we will first create Target Groups which will be used to route the incoming requests to the registered targets which in our case is port 80 and on the HTTP protocol. Instances will be the targets that will be registered in this target group.

Using `aws_lb_target_group_attachment`, we will attach both our web server instances to the target group. target_id will take the id of the instance here and routing of requests will be done on port 80.

`aws_lb` will be used to create our ALB. We will be using the internet faced routing rather than internal routing. The security group attached is the same that was attached to the instances and the load balancer will be set up for all available subnets as taken from the data source.

`aws_lb_listener` will listen to the requests and route as per the action set which in our case will be that it will forward the request to the target group which in turn will route it to one of the instances. This will listen on port 80 with HTTP as protocol as well.

## s3-cdn

Now we will create an S3 bucket, an object storage offering which can be used to store files, images, videos etc. You can compare it with like Google Drive services. We will keep the access open for the public to be able to read the file. The local_exec will download my image from GitHub repository which is to be uploaded to the bucket. It is also created in such a way that the downloaded images will be deleted when the infrastructure is destroyed.

Using `aws_s3_bucket_object`, the download image will be uploaded to S3 bucket with access as public read to be used later in the infrastructure. key is the image name that will be set in the bucket and the source is the path from where the file is to be uploaded.

Now that the S3 bucket is ready. Now top reduce the latency for the S3 access we will be using edge locations. This is a service provided by AWS which allows us to distribute the data in small data centres across the globe to reduce latency from any part of the world and the service that provides this is CloudFront.

As we want to give a user-defined origin ID to the CDN, I will be using variables and locals to create one and to get the final image URL from CDN as well. We will give the domain name and origin ID to the CDN for which it needs to distribute the data.

We can also set a certain restriction (blacklist and whitelist) on the data access like the based geographical location but for now, we have not set any such thing. We have kept the viewer_certificate as true. We have also kept the viewer_certificate as true and viewer protocol policy as default given by AWS services.

## outputs

Using the outputs, we will verify the CDN URL for the image that has been sent to the webpage. Also, we will get our load balancer DNS name, that will be used to access the webserver.

## final

We can see when accessing the web server using a load balancer, the private IP changes to that of the instance.

`depends_on` has been used to make sure all the resources are created in a uniform order and all the dependencies are fulfilled else we can face issues.
