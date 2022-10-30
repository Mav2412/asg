terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  access_key = ""
  secret_key = ""
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = var.cidr_block_vpc

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_dns_hostnames = true
  enable_dns_support = true
  
}
data "aws_ami" "amazon-linux" {
    most_recent = true
    owners = ["amazon"]

    filter {
        name = "name"
        values = ["amzn-ami-hvm-*x86_64-ebs"]
    }  
}

resource "aws_launch_configuration" "terramino" {
name_prefix = "asg"
image_id = data.aws_ami.amazon-linux.id
instance_type = "t2.micro"
security_groups = [aws_security_group.terramino_instance.id]

lifecycle {
  create_before_destroy = true
}
}
resource "aws_autoscaling_group" "terramino" {
   name     = "terramino"
   min_size = 1
   max_size = 3
   desired_capacity = 1
   launch_configuration = aws_launch_configuration.terramino.name
   vpc_zone_identifier = module.vpc.public_subnets

   tag { 
    key = "Name"
    value = "asg - terramino"
    propagate_at_launch = true
   }
   
   lifecycle {
     ignore_changes = [desired_capacity,target_group_arns]
   }
}

resource "aws_lb" "terramino" {
    name ="asg-terramino"
    internal = false
    load_balancer_type = "application"
    security_groups =[aws_security_group.terramino_lb.id]
    subnets = module.vpc.public_subnets
}

resource "aws_lb_listener" "terramino" {
    load_balancer_arn = aws_lb.terramino.arn 
    port  = "80"
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.terramino.arn
    }
}

resource "aws_lb_target_group" "terramino" {
    name = "asg-terramino"
    port = 80
    protocol ="HTTP"
    vpc_id = module.vpc.vpc_id
}
resource "aws_autoscaling_attachment" "terramino" {
    autoscaling_group_name = aws_autoscaling_group.terramino.id
    alb_target_group_arn = aws_lb_target_group.terramino.arn
}

resource "aws_security_group" "terramino_instance" {
    name = "asg-terramino-instance"
    ingress {
        from_port = 80
        to_port   = 80
        protocol  = "tcp"
        security_groups = [aws_security_group.terramino_lb.id]

    }
    egress {
        from_port = 0
        to_port   = 0
        protocol  = "-1"
        security_groups = [aws_security_group.terramino_lb.id]

    }
    vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "terramino_lb" {
    name = "asg-terramino-lb"
    ingress {
        from_port = 80
        to_port   = 80
        protocol  = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port   = 0
        protocol  = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = module.vpc.vpc_id
}

resource "aws_autoscaling_policy" "scale_down" {
  name ="terramino_scale_down"
  autoscaling_group_name = "terramino"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown = 120 
  
}
resource "aws_cloudwatch_metric_alarm" "scale_down" {
  namespace = "terra_scale_down"
  alarm_description = "Monitors CPU utilization"
  alarm_actions = [ aws_autoscaling_policy.scale_down.arn ]
  alarm_name = "terramino_scale_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  metric_name = "CPUutilization"
  threshold = "10"
  evaluation_periods = "2"
  period = "120"
  statistic = "Average"

  dimensions = {
    autoscaling_group_name = aws_autoscaling_group.terramino.name
  }
  
}