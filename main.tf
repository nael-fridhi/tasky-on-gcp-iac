


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
  name                     = "mongodb-subnet"
  ip_cidr_range            = "10.10.1.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Subnet for GKE 
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "gke-subnet"
  ip_cidr_range            = "10.10.2.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Firewall rule to allow SSH and MongoDB (27017) 
resource "google_compute_firewall" "allow_ssh_mongo" {
  name    = "allow-ssh-mongo"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "27017"]
  }

  source_ranges = ["0.0.0.0/0"] # Restrict in production!
  target_tags   = ["mongodb"]
}

###############################################################
# Tasky MongoDB                                               
###############################################################

resource "google_compute_instance" "mongodb" {
  name         = "mongodb-instance"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    network = "default"
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
    sudo systemctl start mongod
    sudo systemctl enable mongod
  EOT

  tags = ["mongodb"]

  service_account {
    scopes = ["cloud-platform"]
  }
}



###############################################################
# Tasky GKE Cluster                                               
###############################################################

resource "google_service_account" "gke-nodes-sa" {
  project      = var.project_id
  provider = google-beta
  account_id   = "${var.app}-gke-nodes-sa"
  display_name = "GKE Nodes Service Account"
  description = "Service Account for GKE nodes to access GCP resources"
}


resource "google_container_cluster" "gke" {
  name     = "${var.app}-gke-cluster"
  location = var.zone
  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.private_subnet.id
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    machine_type = "e2-medium"
    service_account = google_service_account.gke-nodes-sa.email
    tags = ["gke-node"]
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.app}-gke-nodepool"
  cluster    = google_container_cluster.gke.name
  location   = var.zone
  node_count = 1
  node_config {
    machine_type    = "e2-medium"
    service_account = google_service_account.gke-nodes-sa.email
    tags = ["gke-node"]
  }
}