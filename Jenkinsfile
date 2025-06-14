pipeline {
    agent any
    
    environment {
        // Azure credentials - securely managed by Jenkins
        AZURE_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        AZURE_CLIENT_ID = credentials('azure-client-id')
        AZURE_CLIENT_SECRET = credentials('azure-client-secret')
        AZURE_TENANT_ID = credentials('azure-tenant-id')
        
        // SSH key for Ansible
        SSH_KEY = credentials('ssh-private-key')
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out code from Git repository...'
                checkout scm
            }
        }
        
        stage('Validate Azure Credentials') {
            steps {
                script {
                    echo 'Validating Azure authentication...'
                    sh '''
                        export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
                        export ARM_CLIENT_ID=$AZURE_CLIENT_ID
                        export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
                        export ARM_TENANT_ID=$AZURE_TENANT_ID
                        
                        # Test Azure authentication
                        az login --service-principal \
                            --username $ARM_CLIENT_ID \
                            --password $ARM_CLIENT_SECRET \
                            --tenant $ARM_TENANT_ID
                        
                        az account show
                        echo "✅ Azure authentication successful"
                    '''
                }
            }
        }
        
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    echo 'Initializing Terraform...'
                    sh '''
                        export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
                        export ARM_CLIENT_ID=$AZURE_CLIENT_ID
                        export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
                        export ARM_TENANT_ID=$AZURE_TENANT_ID
                        
                        terraform init
                    '''
                }
            }
        }
        
        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    echo 'Creating Terraform execution plan...'
                    sh '''
                        export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
                        export ARM_CLIENT_ID=$AZURE_CLIENT_ID
                        export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
                        export ARM_TENANT_ID=$AZURE_TENANT_ID
                        
                        terraform plan -out=tfplan
                    '''
                }
            }
        }
        
        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    echo 'Provisioning Azure VM with Terraform...'
                    sh '''
                        export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
                        export ARM_CLIENT_ID=$AZURE_CLIENT_ID
                        export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
                        export ARM_TENANT_ID=$AZURE_TENANT_ID
                        
                        terraform apply -auto-approve tfplan
                    '''
                }
            }
        }
        
        stage('Wait for VM') {
            steps {
                echo 'Waiting for VM to be ready for SSH connections...'
                sleep time: 90, unit: 'SECONDS'
            }
        }
        
        stage('Generate Ansible Inventory') {
            steps {
                dir('terraform') {
                    echo 'Extracting VM IP address for Ansible...'
                    script {
                        sh '''
                            export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
                            export ARM_CLIENT_ID=$AZURE_CLIENT_ID
                            export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
                            export ARM_TENANT_ID=$AZURE_TENANT_ID
                            
                            # Get the public IP
                            PUBLIC_IP=$(terraform output -raw public_ip_address)
                            echo "VM Public IP: $PUBLIC_IP"
                            
                            # Create Ansible inventory file
                            cat > ../ansible/inventory << EOF
[webservers]
$PUBLIC_IP ansible_user=azureuser ansible_ssh_private_key_file=/tmp/ssh_key ansible_host_key_checking=false
EOF
                            
                            echo "Ansible inventory created:"
                            cat ../ansible/inventory
                        '''
                    }
                }
            }
        }
        
        stage('Prepare SSH Key') {
            steps {
                echo 'Preparing SSH key for Ansible...'
                sh '''
                    # Write SSH key to temporary file
                    echo "$SSH_KEY" > /tmp/ssh_key
                    chmod 600 /tmp/ssh_key
                    
                    # Test SSH key format
                    ssh-keygen -l -f /tmp/ssh_key || echo "SSH key format check completed"
                '''
            }
        }
        
        stage('Test SSH Connection') {
            steps {
                dir('ansible') {
                    echo 'Testing SSH connection to VM...'
                    retry(5) {
                        sh '''
                            # Test SSH connectivity with Ansible ping
                            ansible webservers -i inventory -m ping -v
                        '''
                    }
                }
            }
        }
        
        stage('Ansible - Install Web Server') {
            steps {
                dir('ansible') {
                    echo 'Installing and configuring Apache web server with Ansible...'
                    sh '''
                        # Run the Ansible playbook
                        ansible-playbook -i inventory install_web.yml -v
                    '''
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                script {
                    dir('terraform') {
                        echo 'Verifying web application deployment...'
                        def publicIP = sh(
                            script: '''
                                export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
                                export ARM_CLIENT_ID=$AZURE_CLIENT_ID
                                export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
                                export ARM_TENANT_ID=$AZURE_TENANT_ID
                                terraform output -raw public_ip_address
                            ''',
                            returnStdout: true
                        ).trim()
                        
                        echo "🌐 Testing web server at: http://${publicIP}"
                        
                        // Verify web server is responding
                        retry(10) {
                            sh """
                                curl -f -s -o /dev/null -w "%{http_code}" http://${publicIP} | grep -q "200"
                                echo "✅ Web server is responding successfully!"
                            """
                        }
                        
                        // Display the content
                        sh """
                            echo "📄 Web page content preview:"
                            curl -s http://${publicIP} | head -20
                        """
                        
                        // Save the URL for easy access
                        writeFile file: 'deployment_url.txt', text: "http://${publicIP}"
                        archiveArtifacts artifacts: 'deployment_url.txt', fingerprint: true
                        
                        echo "🎉 SUCCESS! Your web application is live at: http://${publicIP}"
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo 'Pipeline execution completed!'
            // Clean up temporary files
            sh '''
                # Remove temporary SSH key
                rm -f /tmp/ssh_key
                
                # Remove any temporary credential files
                find . -name "*.tfvars" -delete 2>/dev/null || true
            '''
        }
        success {
            script {
                if (fileExists('terraform/deployment_url.txt')) {
                    def url = readFile('terraform/deployment_url.txt').trim()
                    echo """
                    ✅ DEPLOYMENT SUCCESSFUL! 
                    🌐 Your web application is live at: ${url}
                    📊 All pipeline stages completed successfully
                    🎯 Project objectives achieved:
                       ✓ Jenkins running in Docker
                       ✓ VM provisioned with Terraform  
                       ✓ Web server installed with Ansible
                       ✓ Static site deployed and accessible
                    """
                } else {
                    echo '✅ Pipeline executed successfully!'
                }
            }
        }
        failure {
            echo '''
            ❌ Pipeline failed. Common troubleshooting steps:
            1. Check Azure credentials are valid
            2. Verify SSH key is properly configured
            3. Ensure Azure subscription has sufficient permissions
            4. Check if VM is accessible from Jenkins
            5. Review stage logs for specific error details
            '''
        }
        cleanup {
            echo 'Cleaning up workspace...'
            // Optional: Uncomment to clean workspace after each run
            // cleanWs()
        }
    }
}