variable "location" {
  type    = string
  default = "Norway East"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}