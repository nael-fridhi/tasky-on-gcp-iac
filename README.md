# Tasky on GCP: Infrastructure as Code

This repository provides the **Infrastructure as Code (IaC)** for deploying the **Tasky application** on **Google Cloud Platform (GCP)**. It's an excellent starting point for learning how to leverage various Google Cloud services to deploy a modern application.


[![build](https://github.com/nael-fridhi/tasky-on-gcp-iac/actions/workflows/provision.yml/badge.svg)](https://github.com/nael-fridhi/tasky-on-gcp-iac/actions/workflows/provision.yml) ![](https://img.shields.io/badge/terraform-v1.11-blue)
![](https://img.shields.io/badge/docs-in_progress-orange)
![linesofcode](https://aschey.tech/tokei/github/nael-fridhi/tasky-on-gcp-iac)
---
## Provisioned Resources

This repository provisions the following GCP resources:

* **Virtual Private Cloud (VPC) Network**: A custom VPC network configured with two subnets for organized resource deployment.
* **Artifact Registry**: A private Docker image repository to store the container images for the Tasky application.
* **Compute Engine (GCE) Instance**: A virtual machine instance hosting a **MongoDB cluster**, deployed within one of the VPC subnets.
* **Google Kubernetes Engine (GKE) Cluster**: A private, standard-mode GKE cluster with a single node. **Workload Identity** is enabled for secure authentication of workloads.
* **Cloud Storage Bucket**: A dedicated bucket for storing MongoDB backups.

---
## CI/CD and Authentication

**GitHub Actions** are used for the **Continuous Integration/Continuous Deployment (CI/CD)** of the Terraform configurations. **Workload Identity Federation** (via Workload Identity Pools) is implemented for secure authentication with Google Cloud from GitHub Actions.