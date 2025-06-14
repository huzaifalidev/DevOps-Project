pipeline {
    agent any
    
    environment {
        // Azure credentials
        ARM_CLIENT_ID = credentials('azure-client-id')
        ARM_CLIENT_SECRET = credentials('azure-client-secret')
        ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ARM_TENANT_ID = credentials('azure-tenant-id')
        
        // Terraform variables
        TF_VAR_admin_username = 'azureuser'
        TF_VAR_ssh_public_key_path = './ssh-keys/azure-vm-key.pub'
    }
    
    stages {
        stage('Generate SSH Key') {
            steps {
                dir('terraform') {
                    sh '''
                        # Create ssh-keys directory
                        mkdir -p ssh-keys
                        
                        # Generate SSH key pair if it doesn't exist
                        if [ ! -f ./ssh-keys/azure-vm-key ]; then
                            ssh-keygen -t rsa -b 4096 -f ./ssh-keys/azure-vm-key -N "" -C "jenkins-azure-vm"
                            echo "SSH key pair generated successfully"
                        else
                            echo "SSH key pair already exists"
                        fi
                        
                        # Verify public key exists
                        ls -la ./ssh-keys/
                        cat ./ssh-keys/azure-vm-key.pub
                    '''
                }
            }
        }
        
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                }
            }
        }
        
        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh 'terraform plan'
                }
            }
        }
        
        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    sh 'terraform apply -auto-approve'
                }
            }
        }
        
        stage('Configure Inventory') {
            steps {
                dir('ansible') {
                    script {
                        def publicIP = sh(
                            script: 'cd ../terraform && terraform output -raw public_ip',
                            returnStdout: true
                        ).trim()
                        
                        writeFile file: 'inventory', text: """
[webservers]
azure-vm ansible_host=${publicIP} ansible_user=azureuser ansible_ssh_private_key_file=../terraform/ssh-keys/azure-vm-key
"""
                        
                        sh 'cat inventory'
                    }
                }
            }
        }
        
        stage('Run Ansible Playbook') {
            steps {
                dir('ansible') {
                    sh '''
                        # Wait for VM to be ready
                        sleep 60
                        
                        # Set proper permissions for SSH key
                        chmod 600 ../terraform/ssh-keys/azure-vm-key
                        
                        # Run Ansible playbook
                        ansible-playbook -i inventory playbook.yml --ssh-common-args='-o StrictHostKeyChecking=no'
                    '''
                }
            }
        }
        
        stage('Verify Website') {
            steps {
                script {
                    def publicIP = sh(
                        script: 'cd terraform && terraform output -raw public_ip',
                        returnStdout: true
                    ).trim()
                    
                    sh """
                        # Wait a bit more for services to start
                        sleep 30
                        
                        # Test the website
                        curl -f http://${publicIP} || exit 1
                        echo "Website is accessible at http://${publicIP}"
                    """
                }
            }
        }
    }
    
    post {
        always {
            // Archive SSH keys for future use
            archiveArtifacts artifacts: 'terraform/ssh-keys/*', fingerprint: true, allowEmptyArchive: true
        }
        
        failure {
            echo 'Pipeline failed!'
        }
        
        success {
            echo 'Pipeline completed successfully!'
        }
    }
}