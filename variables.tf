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
  default     = true
}

variable "wait" {
  type        = bool
  description = "Wait for the container to reach an healthy state after creation."
  default     = true
}

variable "image_id" {
  type        = string
  description = "MariaDB image's ID."
}

# Process ------------------------------------------------------------------------------------------

variable "app_uid" {
  type        = number
  description = "UID of the user running the container and owning the data directories."
  default     = 999
}

variable "app_gid" {
  type        = number
  description = "GID of the user running the container and owning the data directories."
  default     = 999
}

variable "privileged" {
  type        = bool
  description = "Run the container in privileged mode."
  default     = false
}

variable "cap_add" {
  type        = set(string)
  description = "Linux capabilities to add to the container, `ALL` for every one."
  default     = []
  validation {
    condition     = length(setsubtract(var.cap_add, local.linux_capabilities)) == 0
    error_message = "Each entry in `cap_add` must be a valid Linux capability name."
  }
}

variable "cap_drop" {
  type        = set(string)
  description = "Linux capabilities to drop from the container, `ALL` for every one."
  default     = []
  validation {
    condition     = length(setsubtract(var.cap_drop, local.linux_capabilities)) == 0
    error_message = "Each entry in `cap_drop` must be a valid Linux capability name."
  }
}

# Networking ---------------------------------------------------------------------------------------

variable "hosts" {
  type        = map(string)
  description = "Add entries to container hosts file."
  default     = {}
}

variable "network_id" {
  type        = string
  description = "Attach the containers to given network."
}

variable "port" {
  type        = number
  description = "Bind the MariaDB port."
  default     = 3306

  validation {
    condition     = var.port == 3306
    error_message = "Having `port` different than 3306 is not yet implemented."
  }
}

# Storage ------------------------------------------------------------------------------------------

variable "data_directory" {
  type        = string
  description = "Where data will be persisted (volumes will be mounted as sub-directories)."
}

variable "secure_file_priv" {
  type        = string
  description = <<-EOT
    Directory of the container the statements of the FILE privilege (`SELECT ... INTO OUTFILE`,
    `LOAD DATA INFILE`) read and write in, out of the data and backup directories. `null` lifts the
    limit, and a FILE account can then plant a dump the restore action loads as root.
  EOT
  default     = "/tmp"
  nullable    = true

  validation {
    condition     = var.secure_file_priv == null || startswith(var.secure_file_priv, "/")
    error_message = "Argument `secure_file_priv` must be an absolute path, or null."
  }
}

# Authentication -----------------------------------------------------------------------------------

variable "root_password" {
  type        = string
  description = "Define root password (if empty, then generated)."
  default     = ""
  sensitive   = true

  # The entrypoint and the actions read the password file through a command substitution, which
  # drops trailing line feeds; a trailing carriage return is the rest of a CRLF line ending.
  validation {
    condition     = !endswith(var.root_password, "\n") && !endswith(var.root_password, "\r")
    error_message = "Argument `root_password` must not end with a line feed or a carriage return."
  }
}
