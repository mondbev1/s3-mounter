include {
  path = find_in_parent_folders("common.hcl")
}

terraform {
  source = "${path_relative_from_include()}/..//s3mount"
}

dependency "eks" {
  config_path = "../../eks"
  mock_outputs = {
    cluster_name = "known-after-apply"
  }
}

dependency "oidc-eks" {
  config_path = "../../oidc-eks"
}

inputs = {
  cluster_name  = dependency.eks.outputs.cluster_name
  bucketName    = "shai-temp-s3mount"
  cluster_type  = "infra"
}
