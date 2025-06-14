pipeline {
  agent any

  environment {
    TF_DIR = './terraform'
    ANSIBLE_DIR = './ansible'

    // Azure credentials (assumes you've added them in Jenkins Credentials Manager)
    ARM_CLIENT_ID       = credentials('ARM_CLIENT_ID')
    ARM_CLIENT_SECRET   = credentials('ARM_CLIENT_SECRET')
    ARM_TENANT_ID       = credentials('ARM_TENANT_ID')
    ARM_SUBSCRIPTION_ID = credentials('ARM_SUBSCRIPTION_ID')
  }

  stages {
    stage('Terraform Init') {
      steps {
        dir("${TF_DIR}") {
          sh 'terraform init'
        }
      }
    }

    stage('Terraform Apply') {
      steps {
        dir("${TF_DIR}") {
          sh 'terraform apply -auto-approve'
        }
      }
    }

    stage('Configure Inventory') {
      steps {
        script {
          def ip = sh(script: "terraform -chdir=${TF_DIR} output -raw public_ip", returnStdout: true).trim()
          writeFile file: "${ANSIBLE_DIR}/hosts.ini", text: """
[web]
${ip} ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/azure-vm-key.pem
          """
        }
      }
    }

    stage('Run Ansible Playbook') {
      steps {
        dir("${ANSIBLE_DIR}") {
          sh 'ansible-playbook -i hosts.ini install_web.yml'
        }
      }
    }

    stage('Verify Website') {
      steps {
        script {
          def ip = sh(script: "terraform -chdir=${TF_DIR} output -raw public_ip", returnStdout: true).trim()
          sh "curl http://${ip}"
        }
      }
    }
  }
}
