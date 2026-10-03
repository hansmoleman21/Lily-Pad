variable "bucket_id" {
  description = "S3 bucket to upload the rendered page into"
  type        = string
}

variable "key" {
  description = "S3 object key (e.g. index.html)"
  type        = string
}

variable "template_path" {
  description = "Path to the .tpl file to render"
  type        = string
}

variable "template_vars" {
  description = "Variables passed to templatefile() for this page"
  type        = map(string)
  default     = {}
}