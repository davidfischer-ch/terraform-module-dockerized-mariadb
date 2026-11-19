terraform {
  required_version = ">= 1.17"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 4.7.0"
    }

    random = {
      # https://github.com/hashicorp/terraform-provider-random/tags
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}
