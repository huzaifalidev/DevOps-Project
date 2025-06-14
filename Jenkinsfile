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
                script {
                    // Create .ssh directory
                    sh 'mkdir -p ~/.ssh'
                    
                    // Write SSH key using Jenkins writeFile to avoid shell substitution issues
                    writeFile file: "${env.HOME}/.ssh/azure-vm-key", text: env.SSH_KEY_CONTENT
                    
                    // Set permissions and validate
                    sh '''#!/bin/bash
                        # Set correct permissions
                        chmod 600 ~/.ssh/azure-vm-key
                        
                        # Debug: Check file details
                        echo "SSH key file details:"
                        ls -la ~/.ssh/azure-vm-key
                        
                        # Check file type
                        echo "File type:"
                        file ~/.ssh/azure-vm-key
                        
                        # Show first line (should be -----BEGIN ... KEY-----)
                        echo "First line of key:"
                        head -1 ~/.ssh/azure-vm-key
                        
                        # Validate SSH key format
                        if ssh-keygen -l -f ~/.ssh/azure-vm-key 2>/dev/null; then
                            echo "✅ SSH key validation successful"
                        else
                            echo "❌ SSH key validation failed - checking if it's the right format"
                            echo "Key content preview (first 100 chars):"
                            head -c 100 ~/.ssh/azure-vm-key
                            echo ""
                            echo "Attempting to fix common issues..."
                            
                            # Try to fix line endings
                            tr -d '\r' < ~/.ssh/azure-vm-key > ~/.ssh/azure-vm-key.tmp
                            mv ~/.ssh/azure-vm-key.tmp ~/.ssh/azure-vm-key
                            chmod 600 ~/.ssh/azure-vm-key
                            
                            # Try validation again
                            if ssh-keygen -l -f ~/.ssh/azure-vm-key 2>/dev/null; then
                                echo "✅ SSH key fixed and validated"
                            else
                                echo "❌ SSH key still invalid"
                                exit 1
                            fi
                        fi
                    '''
                }
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
${publicIP} ansible_user=azureuser ansible_ssh_private_key_file=~/.ssh/azure-vm-key ansible_host_key_checking=false ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
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
                sh '''#!/bin/bash
                    # Get the public IP
                    cd terraform
                    PUBLIC_IP=$(terraform output -raw public_ip_address)
                    echo "Testing SSH to: $PUBLIC_IP"
                    
                    # Test direct SSH connection with timeout
                    echo "Attempting SSH connection..."
                    if timeout 30 ssh -i ~/.ssh/azure-vm-key \
                        -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -o ConnectTimeout=10 \
                        -o BatchMode=yes \
                        azureuser@$PUBLIC_IP 'echo "✅ Direct SSH connection successful!"'; then
                        echo "SSH connection working!"
                    else
                        echo "❌ Direct SSH connection failed, debugging..."
                        echo "Checking if VM is accessible..."
                        ping -c 3 $PUBLIC_IP || echo "VM not pingable"
                        
                        echo "Checking SSH service..."
                        nc -zv $PUBLIC_IP 22 || echo "SSH port not accessible"
                        
                        echo "Trying verbose SSH..."
                        timeout 15 ssh -i ~/.ssh/azure-vm-key \
                            -o StrictHostKeyChecking=no \
                            -o UserKnownHostsFile=/dev/null \
                            -o ConnectTimeout=10 \
                            -v azureuser@$PUBLIC_IP 'echo "test"' 2>&1 | head -30
                    fi
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
                        sh '''
                            sleep 5
                            ansible webservers -i inventory -m ping -v
                        '''
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
                        elif [ -f playbook.yml ]; then
                            ansible-playbook -i inventory playbook.yml -v
                        else
                            echo "❌ No playbook found. Available files:"
                            ls -la
                            echo "Creating a basic web server playbook..."
                            cat > install_web.yml << 'EOF'
---
- name: Install and configure Apache web server
  hosts: webservers
  become: yes
  tasks:
    - name: Update package cache
      apt:
        update_cache: yes
      when: ansible_os_family == "Debian"
    
    - name: Install Apache
      package:
        name: "{{ item }}"
        state: present
      loop:
        - apache2
      when: ansible_os_family == "Debian"
    
    - name: Start and enable Apache
      service:
        name: apache2
        state: started
        enabled: yes
      when: ansible_os_family == "Debian"
    
    - name: Create a simple index page
      copy:
        content: |
          <!DOCTYPE html>
          <html>
          <head>
              <title>DevOps Project Success!</title>
              <style>
                  body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
                  .container { max-width: 600px; margin: 0 auto; }
                  .success { color: #28a745; }
              </style>
          </head>
          <body>
              <div class="container">
                  <h1 class="success">🎉 DevOps Pipeline Success!</h1>
                  <p>Your infrastructure has been successfully deployed using:</p>
                  <ul style="text-align: left; display: inline-block;">
                      <li>Jenkins CI/CD Pipeline</li>
                      <li>Terraform Infrastructure as Code</li>
                      <li>Ansible Configuration Management</li>
                      <li>Azure Cloud Platform</li>
                  </ul>
                  <p><strong>Deployment Date:</strong> {{ ansible_date_time.iso8601 }}</p>
                  <p><strong>Server:</strong> {{ inventory_hostname }}</p>
              </div>
          </body>
          </html>
        dest: /var/www/html/index.html
        owner: www-data
        group: www-data
        mode: '0644'
      when: ansible_os_family == "Debian"
    
    - name: Ensure Apache is running
      service:
        name: apache2
        state: started
      when: ansible_os_family == "Debian"
EOF
                            echo "✅ Created basic playbook, running it now..."
                            ansible-playbook -i inventory install_web.yml -v
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

                        // Wait for web server to be ready
                        echo "Waiting for web server to start..."
                        sleep time: 30, unit: 'SECONDS'

                        retry(10) {
                            script {
                                try {
                                    sh """
                                        curl -fs --connect-timeout 10 --max-time 30 http://${publicIP} > /dev/null
                                        echo '✅ Server reachable!'
                                    """
                                } catch (Exception e) {
                                    echo "❌ Server not reachable yet, retrying..."
                                    sleep time: 10, unit: 'SECONDS'
                                    throw e
                                }
                            }
                        }

                        sh """
                            echo "📄 Web page preview:"
                            curl -s --connect-timeout 10 --max-time 30 http://${publicIP} | head -20
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
6. SSH key format issues
7. Network connectivity problems
Check logs above for exact failure.
            '''
        }
        cleanup {
            echo '🧼 Workspace cleanup complete.'
        }
    }
}