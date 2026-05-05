provider "aws" {
  region  = local.aws_location.region
  profile = local.raw.clouds.aws.profile
}
