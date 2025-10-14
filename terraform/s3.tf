resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  s3_bucket_name = "net-perf-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "results" {
  bucket        = local.s3_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.results.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "enc" {
  bucket = aws_s3_bucket.results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
