# Define provider
provider "google" {
  project = "terraform-ci-cd-project"
  region  = "us-central1"
}

# Variables
variable "project_id" {
  default = "terraform-ci-cd-project"
}

variable "db_password" {
  type        = string
  default     = "test123" 
}

variable "postgres_password" {
  type        = string
  default     = "test123" 
}

resource "google_compute_network" "vpc_network" {
  name                    = "my-custom1-mode-network"
  auto_create_subnetworks = false
  mtu                     = 1460
}
# Create a subnet
resource "google_compute_subnetwork" "default" {
  name          = "my-subnet1"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
}

# Firewall rule for HTTP
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.vpc_network.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Firewall rule for PostgreSQL (port 5432)
resource "google_compute_firewall" "allow_postgres" {
  name    = "allow-postgres"
  network = google_compute_network.vpc_network.id

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["0.0.0.0/0"] # Allow all IPs
}

# Cloud SQL instance for PostgreSQL
resource "google_sql_database_instance" "postgres_instance" {
  name             = "my-db-instance"
  region           = "us-central1"
  database_version = "POSTGRES_14"
  deletion_protection = false
  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = true
      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0"
      }
    }
  }
}

# Create a database
resource "google_sql_database" "my-db" {
  name     = "my-db"
  instance = google_sql_database_instance.postgres_instance.name
}

# Cloud SQL database
resource "google_sql_database" "default_db" {
  name     = "my-database"
  instance = google_sql_database_instance.postgres_instance.name
}

# Create a user
resource "google_sql_user" "admin1" {
  name     = "admin1"
  instance = google_sql_database_instance.postgres_instance.name
  password = var.db_password
}

resource "google_sql_user" "postgres" {
  name     = "postgres"
  instance = google_sql_database_instance.postgres_instance.name
  password = var.postgres_password
}


# Script to run SQL commands for granting privileges and schema access
resource "null_resource" "initialize_db" {
  depends_on = [
    google_sql_user.admin1,
    google_sql_database.my-db,
  ]

  provisioner "local-exec" {
    command = <<EOT
      PGPASSWORD="test123" psql -h ${google_sql_database_instance.postgres_instance.public_ip_address} -U postgres -d my-db -c "GRANT ALL PRIVILEGES ON DATABASE my-db TO admin1;" -c "\\c my-db;" -c "GRANT USAGE ON SCHEMA public TO admin1;" -c "GRANT ALL PRIVILEGES ON SCHEMA public TO admin1;"
    EOT
  }
}

# GKE Cluster
resource "google_container_cluster" "gke_cluster" {
  name       = "my-cluster"
  location   = "us-central1"
  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.default.id
  deletion_protection = false
  remove_default_node_pool = false

  # Node pool definition
  node_pool {
    name = "primary-node-pool"

    node_config {
      machine_type = "e2-medium"
      preemptible  = false
      disk_size_gb = 30
    }

    initial_node_count = 1
  }

  lifecycle {
    prevent_destroy = false # Disable Terraform protection
  }
}