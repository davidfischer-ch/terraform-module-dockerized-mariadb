terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.2"
    }

    random = {
      # https://github.com/hashicorp/terraform-provider-random/tags
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}
