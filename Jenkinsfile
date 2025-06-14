pipeline { 
    agent any

    environment {
        // Azure credentials
        ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ARM_CLIENT_ID = credentials('azure-client-id')
        ARM_CLIENT_SECRET = credentials('azure-client-secret')
        ARM_TENANT_ID = credentials('azure-tenant-id')

        // SSH key - make sure this credential ID exists in Jenkins
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
                echo '🔐 Writing SSH private key to match inventory path...'
                sh '''
                    # Create .ssh directory in Jenkins home
                    mkdir -p ~/.ssh
                    
                    # Debug: Check if SSH_KEY_CONTENT is available
                    echo "SSH_KEY_CONTENT length: ${#SSH_KEY_CONTENT}"
                    echo "First few characters: ${SSH_KEY_CONTENT:0:50}..."
                    
                    # Write SSH key to match inventory path
                    echo "$SSH_KEY_CONTENT" > ~/.ssh/azure-vm-key
                    
                    # Fix potential line ending issues
                    dos2unix ~/.ssh/azure-vm-key 2>/dev/null || true
                    
                    # Set correct permissions
                    chmod 600 ~/.ssh/azure-vm-key
                    
                    # Debug: Check file details
                    echo "SSH key file details:"
                    ls -la ~/.ssh/azure-vm-key
                    echo "File type:"
                    file ~/.ssh/azure-vm-key
                    echo "First line of key:"
                    head -1 ~/.ssh/azure-vm-key
                    
                    # Validate SSH key format
                    if ssh-keygen -l -f ~/.ssh/azure-vm-key; then
                        echo "✅ SSH key validation successful"
                    else
                        echo "❌ SSH key validation failed"
                        echo "Key content (first 200 chars):"
                        head -c 200 ~/.ssh/azure-vm-key
                        exit 1
                    fi
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

                        // Create ansible directory if it doesn't exist
                        sh 'mkdir -p ../ansible'

                        writeFile file: '../ansible/inventory', text: """[webservers]
${publicIP} ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/azure-vm-key ansible_host_key_checking=false
"""

                        echo "Inventory file created:"
                        sh 'cat ../ansible/inventory'
                    }
                }
            }
        }

        stage('Debug SSH Connection') {
            steps {
                echo '🔍 Testing direct SSH connection...'
                sh '''
                    # Get the public IP
                    cd terraform
                    PUBLIC_IP=$(terraform output -raw public_ip_address)
                    echo "Testing SSH to: $PUBLIC_IP"
                    
                    # Test direct SSH connection
                    ssh -i ~/.ssh/azure-vm-key -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                        azureuser@$PUBLIC_IP 'echo "✅ Direct SSH connection successful!"' || {
                        echo "❌ Direct SSH connection failed"
                        echo "Debugging SSH connection..."
                        ssh -i ~/.ssh/azure-vm-key -o StrictHostKeyChecking=no -o ConnectTimeout=10 -v \
                            azureuser@$PUBLIC_IP 'echo "test"' 2>&1 | head -20
                    }
                '''
            }
        }

        stage('Test SSH Connection') {
            steps {
                dir('ansible') {
                    echo '🔗 Testing SSH connection using Ansible ping...'
                    sh '''
                        echo "Current directory: $(pwd)"
                        echo "Inventory file contents:"
                        cat inventory
                        echo "Testing Ansible ping..."
                    '''
                    retry(3) {
                        sh 'ansible webservers -i inventory -m ping -v'
                    }
                }
            }
        }

        stage('Ansible - Install Web Server') {
            steps {
                dir('ansible') {
                    echo '🛠️ Installing Apache web server via Ansible...'
                    sh '''
                        echo "Available playbooks:"
                        ls -la *.yml 2>/dev/null || echo "No .yml files found"
                        
                        # Check if playbook exists
                        if [ -f install_web.yml ]; then
                            ansible-playbook -i inventory install_web.yml -v
                        else
                            echo "❌ install_web.yml not found. Available files:"
                            ls -la
                            exit 1
                        fi
                    '''
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
                rm -f ~/.ssh/azure-vm-key
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
5. Missing SSH key or wrong credential ID
Check logs above for exact failure.
            '''
        }
        cleanup {
            echo '🧼 Workspace cleanup complete.'
        }
    }
}