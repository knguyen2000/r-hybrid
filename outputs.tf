output "results_bucket_name" {
  description = "Name of the S3 bucket for storing results"
  value       = aws_s3_bucket.results.bucket
}

output "server_a_private_ip" {
  description = "Private IP of the server instance in AZ A (for intra-AZ tests)"
  value       = aws_instance.server_a.private_ip
}

output "server_b_private_ip" {
  description = "Private IP of the server instance in AZ B (for cross-AZ tests)"
  value       = aws_instance.server_b.private_ip
}

output "client_public_ip" {
  description = "Public IP of the client instance"
  value       = aws_instance.client.public_ip
}

output "client_private_ip" {
  description = "Private IP of the client instance, for agents to monitor"
  value       = aws_instance.client.private_ip
}

output "client_instance_id" {
  description = "Instance ID of the client, needed for SSM targeting by agents"
  value       = aws_instance.client.id
}

output "client_name_tag" {
  description = "The 'Name' tag of the client instance"
  value       = aws_instance.client.tags["Name"]
}