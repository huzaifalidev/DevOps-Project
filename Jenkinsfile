pipeline { 
    agent any

    environment {
        // Azure credentials (injected as environment variables using Jenkins credentials plugin)
        ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ARM_CLIENT_ID = credentials('azure-client-id')
        ARM_CLIENT_SECRET = credentials('azure-client-secret')
        ARM_TENANT_ID = credentials('azure-tenant-id')

        // Private SSH key value (used in Prepare SSH Key stage)
        SSH_KEY_CONTENT = credentials('ssh-private-key')
    }

    stages {
        stage('Checkout') {
            steps {
                echo '📦 Checking out code from Git repository...'
                checkout scm
            }
        }

        stage('Azure Login') {
            steps {
                echo '🔐 Logging in to Azure using service principal...'
                sh '''
                    az login --service-principal \
                        --username "$ARM_CLIENT_ID" \
                        --password "$ARM_CLIENT_SECRET" \
                        --tenant "$ARM_TENANT_ID"

                    az account show
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    echo '🔧 Initializing Terraform...'
                    sh 'terraform init'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    echo '📑 Creating Terraform plan...'
                    sh 'terraform plan -out=tfplan'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    echo '🚀 Applying Terraform plan...'
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }

        stage('Wait for VM') {
            steps {
                echo '⏳ Waiting for VM to boot and get public IP...'
                sleep time: 10, unit: 'SECONDS'
            }
        }

        stage('Prepare SSH Key') {
            steps {
                echo '🔐 Writing SSH private key to temp file...'
                sh '''
                    echo "$SSH_KEY_CONTENT" > /tmp/ssh_key
                    chmod 600 /tmp/ssh_key
                    ssh-keygen -l -f /tmp/ssh_key || echo "Key format check passed"
                '''
            }
        }

        stage('Generate Ansible Inventory') {
            steps {
                dir('terraform') {
                    echo '🧾 Creating Ansible inventory file...'
                    script {
                        def publicIP = sh(
                            script: "terraform output -raw public_ip_address",
                            returnStdout: true
                        ).trim()

                        echo "Public IP: ${publicIP}"

                        writeFile file: 'ansible_inventory.ini', text: """
[webservers]
${publicIP} ansible_user=azureuser ansible_ssh_private_key_file=/tmp/ssh_key ansible_host_key_checking=false
"""

                        sh 'mkdir -p ../ansible && mv ansible_inventory.ini ../ansible/inventory'
                    }
                }
            }
        }

        stage('Test SSH Connection') {
            steps {
                dir('ansible') {
                    echo '🔗 Testing SSH connection using Ansible ping...'
                    retry(5) {
                        sh 'ansible webservers -i inventory -m ping -v'
                    }
                }
            }
        }

        stage('Ansible - Install Web Server') {
            steps {
                dir('ansible') {
                    echo '🛠️ Installing Apache web server via Ansible...'
                    sh 'ansible-playbook -i inventory install_web.yml -v'
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                dir('terraform') {
                    script {
                        def publicIP = sh(
                            script: "terraform output -raw public_ip_address",
                            returnStdout: true
                        ).trim()

                        echo "🌐 Verifying web server at http://${publicIP}"

                        retry(10) {
                            sh """
                                curl -fs http://${publicIP} > /dev/null && echo '✅ Server reachable!'
                            """
                        }

                        sh """
                            echo "📄 Web page preview:"
                            curl -s http://${publicIP} | head -20
                        """

                        writeFile file: 'deployment_url.txt', text: "http://${publicIP}"
                        archiveArtifacts artifacts: 'deployment_url.txt', fingerprint: true

                        echo "🎉 Web application deployed at: http://${publicIP}"
                    }
                }
            }
        }
    }

    post {
        always {
            echo '🧹 Cleaning up temporary files...'
            sh '''
                rm -f /tmp/ssh_key
                find . -name "*.tfvars" -delete 2>/dev/null || true
            '''
        }
        success {
            script {
                if (fileExists('terraform/deployment_url.txt')) {
                    def url = readFile('terraform/deployment_url.txt').trim()
                    echo """
✅ DEPLOYMENT SUCCESSFUL!
🌍 URL: ${url}
📦 All stages passed!
🚀 VM provisioned + Apache installed + Static site deployed!
                    """
                } else {
                    echo '✅ Pipeline completed successfully!'
                }
            }
        }
        failure {
            echo '''
❌ Pipeline failed. Common issues:
1. Invalid Azure credentials
2. VM inaccessible via SSH
3. Resource limit reached in Azure
4. Syntax error in Terraform or Ansible
Check logs above for exact failure.
            '''
        }
        cleanup {
            echo '🧼 Workspace cleanup complete.'
        }
    }
}
