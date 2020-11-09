# aws provider
provider "aws" {
    profile = "eugene-test"
    region  = "us-west-1"
}

# get default vpc of account
data "aws_vpc" "selected" {
    default = true
}

# get live availability zones list
data "aws_availability_zones" "available" {
    state = "available"
}

# get the list of subnet ids in selected vpc
data "aws_subnet_ids" "example" {
    vpc_id = data.aws_vpc.selected.id
}
