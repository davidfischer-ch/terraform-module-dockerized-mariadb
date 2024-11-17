variable "identifier" {
  type        = string
  description = "Identifier (must be unique, used to name resources)."
  validation {
    condition     = regex("^[a-z]+(-[a-z0-9]+)*$", var.identifier) != null
    error_message = "Argument `identifier` must match regex ^[a-z]+(-[a-z0-9]+)*$."
  }
}

variable "enabled" {
  type        = bool
  description = "Toggle the containers (started or stopped)."
}

variable "wait" {
  type        = bool
  default     = true
  description = "Wait for the container to reach an healthy state after creation."
}

variable "image_id" {
  type        = string
  description = "MariaDB image's ID."
}

variable "data_directory" {
  type        = string
  description = "Where data will be persisted (volumes will be mounted as sub-directories)."
}

# Database -----------------------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Database name"
}

# Authentication -----------------------------------------------------------------------------------

variable "user" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

# Networking ---------------------------------------------------------------------------------------

variable "hosts" {
  type        = map(string)
  default     = {}
  description = "Add entries to container hosts file."
}

variable "network_id" {
  type        = string
  description = "Attach the containers to given network."
}

variable "port" {
  type    = number
  default = 3306

  validation {
    condition     = var.port == 3306
    error_message = "Having `port` different than 3306 is not yet implemented."
  }
}
