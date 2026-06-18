variable "name_prefix" {
  type = string
}

variable "location" {
  type    = string
  default = "denmarkeast"
}

variable "cloudflare_zone_id" {
  type = string
}

variable "github_repo_url" {
  type    = string
  default = "https://github.com/ua-academy-projects/coin-ops.git"
}

variable "git_branch" {
  type    = string
  default = "*/kurdupel"
}