variable "project_id" {
  description = "The ID of the GCP project where resources will be created."
  type        = string
  default     = "clgcporg10-166"
}
variable "region" {
  description = "The GCP region where resources will be created."
  type        = string
  default     = "us-central1"

}
variable "zone" {
  description = "The GCP zone where resources will be created."
  type        = string
  default     = "us-central1-a"
}

variable "app" {
  description = "The name of the application."
  type        = string
  default     = "tasky"
}