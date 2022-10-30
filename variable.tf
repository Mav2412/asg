# Variable declarations
 variable "aws_region" {
    description = "aws region"
    type = string
    default = "us-west-2"
 }

 variable "cidr_block_vpc" {
    description = "block cidr for vpc"
    type = string
    default = "10.0.0.0/16"
   
 }