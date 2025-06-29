# DevOps Project: One-Click Jenkins Pipeline Deployment

This project demonstrates a fully automated DevOps pipeline using Jenkins, Docker, Terraform, and Ansible to provision and deploy a web application on Azure.

## 🎯 Objective

Build a fully automated DevOps pipeline that:
1. Provisions a VM on Azure using Terraform
2. Installs a web server on that VM using Ansible
3. Deploys a static web app to that server via Ansible
4. Runs all these steps from a single Jenkins pipeline

## 🛠️ Technology Stack

| Tool | Purpose |
|------|---------|
| Docker | Host Jenkins in a container |
| Jenkins | Automate the workflow |
| Terraform | Provision the virtual machine |
| Ansible | Configure the VM and deploy the web app |
| Azure | Host the virtual machine |
| Git | Store all configuration files |

## 📁 Project Structure