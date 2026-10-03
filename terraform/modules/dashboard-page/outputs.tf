output "key" {
  description = "S3 key of the uploaded page"
  value       = aws_s3_object.page.key
}