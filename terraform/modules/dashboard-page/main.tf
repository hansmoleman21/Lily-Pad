locals {
  rendered = templatefile(var.template_path, var.template_vars)
}

resource "aws_s3_object" "page" {
  bucket        = var.bucket_id
  key           = var.key
  content_type  = "text/html"
  content       = local.rendered
  etag          = md5(local.rendered)
  cache_control = "no-cache" # HTML is the entry point: always revalidate, so config baked into it (e.g. the Okta client ID) takes effect immediately
}