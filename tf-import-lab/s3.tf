# __generated__ by OpenTofu
# Please review these resources and move them into your main configuration files.

# __generated__ by OpenTofu
resource "aws_s3_bucket" "legacy_reports" {
  bucket              = "legacy-reports-482112969377"
  force_destroy       = null
  object_lock_enabled = false
  tags = {
    Team      = "finance"
    Managedby = "opentofu"
    Purpose   = "lab-test"

  }
}

removed {
  from = aws_s3_bucket_versioning.legacy_reports

  lifecycle {
    destroy = false
  }
}