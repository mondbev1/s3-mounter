variable "cluster_name" {
  type = string
}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

variable "cluster_type" {
  description = "cluster type - app|infra "
  type = string
}

variable "bucketName" {
  type = string
}

locals {
  s3mount_namespace = "s3mount"
  s3mount_sa_name = "s3mount"
  s3mount_oidc_subjects = [
    "system:serviceaccount:${local.s3mount_namespace}:${local.s3mount_sa_name}"
  ]
  s3mount_iam_policy_document = <<EOT
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::shai-temp-s3mount"
            ]
        }
    ]
}
EOT
  s3mount_iam_role_name = "S3mount-${var.cluster_name}"
}

resource aws_iam_policy s3mount {
  name        = local.s3mount_iam_role_name
  path        = "/"
  description = "for s3mount of cluster ${var.cluster_name}"

  policy = local.s3mount_iam_policy_document
}


data tls_certificate oidc_issuer {
  url = data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}

# https://github.com/terraform-aws-modules/terraform-aws-iam/blob/master/examples/iam-assumable-role-with-oidc/main.tf
# https://github.com/terraform-aws-modules/terraform-aws-iam/tree/master/modules/iam-assumable-role-with-oidc
module iam_assumable_role_s3mount {
  source      = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version     = "4.3.0"
  create_role = true

  role_name = local.s3mount_iam_role_name

  provider_url  = data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer
  provider_urls = [data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer]

  role_policy_arns = [
    aws_iam_policy.s3mount.arn,
  ]

  oidc_fully_qualified_subjects = local.s3mount_oidc_subjects
}

provider helm {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
  debug = true
  experiments {
    manifest = true
  }
}

resource helm_release s3mount {
  name              = "s3mount"
  chart             = "${path.module}/chart"
  namespace         = "s3mount"
  create_namespace  = true
  dependency_update = true

  set {
    name  = "iamRoleARN"
    value = "${module.iam_assumable_role_s3mount.iam_role_arn}"
  }
  set {
    name  = "bucketName"
    value = "${var.bucketName}"
  }
  set {
    name  = "serviceAccount.name"
    value = "${local.s3mount_sa_name}"
  }

  values = [
    file("${path.module}/chart/values.yaml")
  ]
}