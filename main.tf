###############################################################
# Tasky Network                                               
###############################################################
# Tasky VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.app}-vpc"
  auto_create_subnetworks = false
}

# Subnet for MongoDB 
resource "google_compute_subnetwork" "public_subnet" {
  name                     = "${var.app}-mongodb-subnet"
  ip_cidr_range            = "10.10.1.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Subnet for GKE 
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "${var.app}-gke-subnet"
  ip_cidr_range            = "10.10.2.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.app}-gke-pods"
    ip_cidr_range = "192.168.0.0/18"
  }
  secondary_ip_range {
    range_name    = "${var.app}-gke-services"
    ip_cidr_range = "192.169.64.0/18"
  }
}

# Firewall rule to allow SSH and MongoDB (27017) 
resource "google_compute_firewall" "allow_ssh_mongo" {
  name    = "${var.app}-mongo-fw"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "27017"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongodb"]
}

###############################################################
# Tasky MongoDB                                               
###############################################################

resource "google_compute_instance" "mongodb" {
  name         = "${var.app}-mongodb-instance"
  machine_type = "e2-medium"
  zone         = "us-central1-a"
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }
  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.public_subnet.id
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y gnupg curl
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org

    # Install Google Cloud SDK
    sudo apt-get install -y apt-transport-https ca-certificates gnupg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    sudo apt-get update && sudo apt-get install -y google-cloud-sdk


    # Create backup script
    cat <<EOF | sudo tee /usr/local/bin/mongo_backup.sh
    #!/bin/bash
    TIMESTAMP=\$(date +%F-%H%M%S)
    BACKUP_PATH="/tmp/mongo-backup-\$TIMESTAMP"
    mongodump --db=go-mongodb --out \$BACKUP_PATH
    gsutil cp -r \$BACKUP_PATH gs://tasky-db-backups/mongo-backups/
    rm -rf \$BACKUP_PATH
    EOF
    sudo chmod +x /usr/local/bin/mongo_backup.sh

    # Create cron job for daily backup at 2 AM
    (sudo crontab -l ; echo "0 2 * * * /usr/local/bin/mongo_backup.sh") | sudo crontab -

    sudo systemctl start mongod
    sudo systemctl enable mongod
  EOT

  tags = ["mongodb"]
  service_account {
    scopes = ["cloud-platform"]
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

###############################################################
# Tasky GKE Cluster                                               
###############################################################

resource "google_service_account" "gke-nodes-sa" {
  project      = var.project_id
  provider     = google-beta
  account_id   = "${var.app}-gke-nodes-sa"
  display_name = "GKE Nodes Service Account"
  description  = "Service Account for GKE nodes to access GCP resources"
}


resource "google_container_cluster" "gke" {
  provider                 = google-beta
  name                     = "${var.app}-gke-cluster"
  location                 = var.zone
  network                  = google_compute_network.vpc.id
  subnetwork               = google_compute_subnetwork.private_subnet.id
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false
  datapath_provider        = "ADVANCED_DATAPATH"

  private_cluster_config {
    enable_private_nodes = true
  }
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "88.163.242.155/32"
      display_name = "Home IP"
    }
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = "${var.app}-gke-pods"
    services_secondary_range_name = "${var.app}-gke-services"
  }
  secret_manager_config {
    enabled = true
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  node_config {
    machine_type    = "e2-medium"
    service_account = google_service_account.gke-nodes-sa.email
    tags            = ["gke-node"]
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.app}-gke-nodepool"
  cluster    = google_container_cluster.gke.name
  location   = var.zone
  node_count = 1
  node_config {
    machine_type    = "e2-medium"
    disk_size_gb    = 30
    service_account = google_service_account.gke-nodes-sa.email
    tags            = ["gke-node"]
  }
}

###############################################################
# Storage Bucket & Artifact Registry                                         
###############################################################
resource "google_storage_bucket" "tasky_bucket" {
  name          = "${var.app}-db-backups"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
}

resource "google_artifact_registry_repository" "tasky_repo" {
  provider      = google-beta
  repository_id = "${var.app}-docker-images"
  location      = var.region
  format        = "DOCKER"
  description   = "Artifact Registry repository for Tasky application"
}