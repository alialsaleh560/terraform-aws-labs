variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "users" {
  type = map(object({
    role  = string
    admin = optional(bool, false)
  }))
}