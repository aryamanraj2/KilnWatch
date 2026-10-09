resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "main" {
  identifier                  = "${var.project_name}-${var.environment}-db"
  engine                      = "postgres"
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  max_allocated_storage       = 100
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.main.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  storage_encrypted           = true
  backup_retention_period     = 1
  deletion_protection         = false
  skip_final_snapshot         = true
  auto_minor_version_upgrade  = true
  apply_immediately           = true
}
# After connecting as a database administrator, enable PostGIS:
# CREATE EXTENSION IF NOT EXISTS postgis;
# Terraform provisions the RDS instance but does not execute SQL schema migrations.
