output "server_ip" {
  value = aws_instance.server.public_ip
}

output "client_ips" {
  value = [for c in aws_instance.client : c.public_ip]
}

output "client_name_tags" {
  value = [for c in aws_instance.client : c.tags["Name"]]
}

output "s3_bucket_name" {
  value = aws_s3_bucket.results.bucket
}
