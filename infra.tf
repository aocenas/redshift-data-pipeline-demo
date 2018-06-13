provider "aws" {
  region = "us-east-1"
  profile = "test-profile"
}

provider "random" {}
resource "random_pet" "bucket" {
  length = 3
}

data "aws_region" "current" {}


#
# S3
#

resource "aws_s3_bucket" "s3_bucket" {
  bucket = "${random_pet.bucket.id}.test-pipeline"
  acl    = "private"
}

resource "aws_s3_bucket_object" "jsonpath_config" {
  bucket = "${aws_s3_bucket.s3_bucket.bucket}"
  key    = "JSONPaths.json"
  source = "./JSONPaths.json"
}


#
# IAM
#

resource "aws_iam_role" "test_pipeline_role" {
  name = "firehose_test_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "firehose.amazonaws.com",
          "redshift.amazonaws.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "test_pipeline_role_policy" {
   name = "pipeline_test_role_policy"
   role = "${aws_iam_role.test_pipeline_role.id}"
   policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.s3_bucket.arn}",
        "${aws_s3_bucket.s3_bucket.arn}/*"
      ]
    }
  ]
}
EOF
}


#
# VPC
#

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "simple-example"

  cidr = "10.0.0.0/16"

  azs  = ["us-east-1a"]
  public_subnets = ["10.0.1.0/24"]
}

resource "aws_redshift_subnet_group" "redshift" {
  name        = "demo-redshift-subnet"
  description = "Redshift subnet group"
  subnet_ids  = ["${module.vpc.public_subnets}"]
}

module "sg" {
  source = "terraform-aws-modules/security-group/aws//modules/redshift"

  name   = "demo-redshift"
  vpc_id = "${module.vpc.vpc_id}"

  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules = ["all-all"]
}


#
# Reshift
#
resource "aws_redshift_cluster" "test_pipeline_cluster" {
  cluster_identifier = "test-pipeline-cluster"
  database_name      = "test"
  master_username    = "testuser"
  master_password    = "T3stPass"
  node_type          = "dc2.large"
  cluster_type       = "single-node"
  cluster_subnet_group_name = "${aws_redshift_subnet_group.redshift.name}"
  vpc_security_group_ids = ["${module.sg.this_security_group_id}"]
  skip_final_snapshot = true
  publicly_accessible = true
  iam_roles = ["${aws_iam_role.test_pipeline_role.arn}"]
  provisioner "local-exec" {
    command = "psql \"postgresql://${self.master_username}:${self.master_password}@${self.endpoint}/${self.database_name}\" -f ./redshift_table.sql"
  }
}


#
# Firehose
#

resource "aws_kinesis_firehose_delivery_stream" "test_pipeline_firehose" {
  name        = "test_pipeline_firehose"
  destination = "redshift"

  s3_configuration {
    role_arn   = "${aws_iam_role.test_pipeline_role.arn}"
    bucket_arn = "${aws_s3_bucket.s3_bucket.arn}"
    buffer_interval = 60
  }

  redshift_configuration {
    role_arn           = "${aws_iam_role.test_pipeline_role.arn}"
    cluster_jdbcurl    = "jdbc:redshift://${aws_redshift_cluster.test_pipeline_cluster.endpoint}/${aws_redshift_cluster.test_pipeline_cluster.database_name}"
    username           = "${aws_redshift_cluster.test_pipeline_cluster.master_username}"
    password           = "${aws_redshift_cluster.test_pipeline_cluster.master_password}"
    data_table_name    = "data"
    copy_options       = "json 's3://${aws_s3_bucket.s3_bucket.bucket}/${aws_s3_bucket_object.jsonpath_config.key}' region '${data.aws_region.current.name}' timeformat 'auto'"
  }
}
