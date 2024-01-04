variable "location" {
  type = string
  default = "eastus"
}

variable "controller_count" {
  type = number
  default = 3
}

variable "worker_count" {
  type = number
  default = 2
}