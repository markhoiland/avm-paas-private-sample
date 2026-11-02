variable "subscription_id" {
  type        = string
  description = "Azure subscription containing the existing resource group."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Existing resource group. This deployment does not create or own it."
  nullable    = false
}

variable "location" {
  type        = string
  description = "Azure deployment region; null uses the existing resource group's location."
  default     = null
}

variable "name_prefix" {
  type        = string
  description = "Globally unique lowercase prefix for App Service and SQL names; 3-40 letters, digits or internal hyphens."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name_prefix))
    error_message = "Use 3-40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "sql_admin_object_id" {
  type        = string
  description = "Microsoft Entra object ID of the SQL administrator user or group, not an application/client ID."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.sql_admin_object_id))
    error_message = "Supply the administrator's Microsoft Entra object UUID."
  }
}

variable "sql_admin_login" {
  type        = string
  description = "Microsoft Entra SQL administrator login/display name matching sql_admin_object_id."
  nullable    = false

  validation {
    condition     = length(trimspace(var.sql_admin_login)) > 0
    error_message = "The administrator login must not be empty."
  }
}
