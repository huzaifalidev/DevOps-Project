pipeline { 
    // Option 1: Use built-in node (most common solution)
    agent { label 'built-in' }
    
    // Option 2: If you want to use any available agent, try:
    // agent any
    
    // Option 3: If you have specific node labels, use:
    // agent { label 'linux' }
    // agent { label 'docker' }
    
    // Option 4: Use none and specify agent per stage
    // agent none

    environment {
        // Azure credentials
        ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ARM_CLIENT_ID = credentials('azure-client-id')
        ARM_CLIENT_SECRET = credentials('azure-client-secret')
        ARM_TENANT_ID = credentials('azure-tenant-id')
        SSH_KEY_CONTENT = credentials('ssh-private-key')
    }

    stages {
        stage('Checkout') {
            // If using agent none above, specify agent per stage:
            // agent { label 'built-in' }
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
                sleep time: 60, unit: 'SECONDS'
            }
        }

        stage('Prepare SSH Key') {
            steps {
                echo '🔐 Preparing SSH private key...'
                script {
                    sh 'mkdir -p ${WORKSPACE}/.ssh'
                    
                    withCredentials([string(credentialsId: 'ssh-private-key', variable: 'SSH_KEY_CONTENT')]) {
                        sh '''#!/bin/bash
                            echo "$SSH_KEY_CONTENT" > ${WORKSPACE}/.ssh/azure-vm-key
                            chmod 600 ${WORKSPACE}/.ssh/azure-vm-key
                            chmod 700 ${WORKSPACE}/.ssh
                            
                            echo "SSH key file details:"
                            ls -la ${WORKSPACE}/.ssh/azure-vm-key
                            echo "SSH key has $(wc -l < ${WORKSPACE}/.ssh/azure-vm-key) lines"
                            
                            echo "First line of key:"
                            head -1 ${WORKSPACE}/.ssh/azure-vm-key
                            echo "Last line of key:"
                            tail -1 ${WORKSPACE}/.ssh/azure-vm-key
                            
                            if head -1 ${WORKSPACE}/.ssh/azure-vm-key | grep -E "^-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----" > /dev/null; then
                                echo "✅ SSH key header format appears valid"
                            else
                                echo "❌ SSH key format invalid. Expected format:"
                                echo "-----BEGIN [RSA|OPENSSH|EC] PRIVATE KEY-----"
                                echo "Got: $(head -1 ${WORKSPACE}/.ssh/azure-vm-key | tr -d '\\r\\n')"
                                exit 1
                            fi
                            
                            if tail -1 ${WORKSPACE}/.ssh/azure-vm-key | grep -E "^-----END (RSA |OPENSSH |EC )?PRIVATE KEY-----" > /dev/null; then
                                echo "✅ SSH key footer format appears valid"
                            else
                                echo "❌ SSH key footer invalid. Expected format:"
                                echo "-----END [RSA|OPENSSH|EC] PRIVATE KEY-----"
                                echo "Got: $(tail -1 ${WORKSPACE}/.ssh/azure-vm-key | tr -d '\\r\\n')"
                                exit 1
                            fi
                            
                            if ssh-keygen -l -f ${WORKSPACE}/.ssh/azure-vm-key 2>/dev/null; then
                                echo "✅ SSH key validation successful"
                            else
                                echo "❌ SSH key validation failed - key is corrupted or invalid format"
                                echo "Trying to identify the issue..."
                                
                                if grep -q "\\r" ${WORKSPACE}/.ssh/azure-vm-key; then
                                    echo "Found Windows line endings (\\r) - this might be the issue"
                                    tr -d '\\r' < ${WORKSPACE}/.ssh/azure-vm-key > ${WORKSPACE}/.ssh/azure-vm-key.tmp
                                    mv ${WORKSPACE}/.ssh/azure-vm-key.tmp ${WORKSPACE}/.ssh/azure-vm-key
                                    chmod 600 ${WORKSPACE}/.ssh/azure-vm-key
                                    echo "Cleaned line endings, retesting..."
                                    
                                    if ssh-keygen -l -f ${WORKSPACE}/.ssh/azure-vm-key 2>/dev/null; then
                                        echo "✅ SSH key validation successful after cleanup"
                                    else
                                        echo "❌ SSH key still invalid after cleanup"
                                        exit 1
                                    fi
                                else
                                    echo "❌ SSH key validation failed - please regenerate your key pair"
                                    exit 1
                                fi
                            fi
                        '''
                    }
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
                        sh 'mkdir -p ../ansible'

                        writeFile file: '../ansible/inventory', text: """[webservers]
${publicIP} ansible_user=azureuser ansible_ssh_private_key_file=${WORKSPACE}/.ssh/azure-vm-key ansible_host_key_checking=false ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30'

[all:vars]
ansible_python_interpreter=/usr/bin/python3
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
                    cd terraform
                    PUBLIC_IP=$(terraform output -raw public_ip_address)
                    echo "Testing SSH to: $PUBLIC_IP"
                    
                    echo "Waiting additional 30 seconds for VM to be fully ready..."
                    sleep 30
                    
                    echo "Checking if VM is accessible..."
                    if timeout 10 ping -c 3 $PUBLIC_IP; then
                        echo "✅ VM is pingable"
                    else
                        echo "⚠️  VM not pingable (this is normal for Azure VMs with restricted ICMP)"
                    fi
                    
                    echo "Checking SSH service availability..."
                    for i in {1..5}; do
                        if timeout 10 nc -zv $PUBLIC_IP 22 2>/dev/null; then
                            echo "✅ SSH port is accessible"
                            break
                        else
                            echo "⏳ SSH port check attempt $i/5 failed, waiting 10 seconds..."
                            sleep 10
                        fi
                    done
                    
                    if ! timeout 10 nc -zv $PUBLIC_IP 22 2>/dev/null; then
                        echo "❌ SSH port not accessible after 5 attempts"
                        exit 1
                    fi
                    
                    echo "Verifying SSH key file..."
                    ls -la ${WORKSPACE}/.ssh/azure-vm-key
                    
                    echo "Attempting SSH connection (5 attempts)..."
                    for i in {1..5}; do
                        echo "SSH attempt $i/5..."
                        if timeout 30 ssh -i ${WORKSPACE}/.ssh/azure-vm-key \
                            -o StrictHostKeyChecking=no \
                            -o UserKnownHostsFile=/dev/null \
                            -o ConnectTimeout=30 \
                            -o BatchMode=yes \
                            -o LogLevel=ERROR \
                            azureuser@$PUBLIC_IP 'echo "✅ SSH connection successful on attempt '$i'!"'; then
                            echo "✅ SSH connection established!"
                            exit 0
                        else
                            echo "❌ SSH attempt $i failed"
                            if [ $i -eq 5 ]; then
                                echo "All SSH attempts failed. Running verbose SSH for debugging..."
                                timeout 30 ssh -i ${WORKSPACE}/.ssh/azure-vm-key \
                                    -o StrictHostKeyChecking=no \
                                    -o UserKnownHostsFile=/dev/null \
                                    -o ConnectTimeout=30 \
                                    -vvv azureuser@$PUBLIC_IP 'echo "test"' 2>&1 | head -50
                                exit 1
                            else
                                echo "Waiting 15 seconds before next attempt..."
                                sleep 15
                            fi
                        fi
                    done
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
                        echo "Testing Ansible ping with retries..."
                    '''
                    retry(5) {
                        sh '''
                            echo "Waiting 10 seconds before Ansible ping..."
                            sleep 10
                            echo "Running Ansible ping..."
                            ansible webservers -i inventory -m ping -v --timeout=60
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
                        
                        if [ -f install_web.yml ]; then
                            ansible-playbook -i inventory install_web.yml -v --timeout=120
                        elif [ -f playbook.yml ]; then
                            ansible-playbook -i inventory playbook.yml -v --timeout=120
                        else
                            echo "❌ No playbook found. Available files:"
                            ls -la
                            echo "Creating a basic web server playbook..."
                            cat > install_web.yml << 'EOF'
---
- name: Install and configure Apache web server
  hosts: webservers
  become: yes
  gather_facts: yes
  tasks:
    - name: Wait for system to be ready
      wait_for_connection:
        timeout: 300
        delay: 5

    - name: Update package cache
      apt:
        update_cache: yes
        cache_valid_time: 3600
      retries: 3
      delay: 10
      
    - name: Install Apache
      apt:
        name: apache2
        state: present
        update_cache: yes
      retries: 3
      delay: 10
    
    - name: Start and enable Apache
      systemd:
        name: apache2
        state: started
        enabled: yes
        daemon_reload: yes
    
    - name: Create a simple index page
      copy:
        content: |
          <!DOCTYPE html>
          <html>
          <head>
              <title>DevOps Project Success!</title>
              <style>
                  body { 
                      font-family: Arial, sans-serif; 
                      text-align: center; 
                      margin-top: 50px; 
                      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                      color: white;
                      min-height: 100vh;
                  }
                  .container { 
                      max-width: 600px; 
                      margin: 0 auto; 
                      padding: 20px;
                      background: rgba(255,255,255,0.1);
                      border-radius: 10px;
                      backdrop-filter: blur(10px);
                  }
                  .success { color: #00ff88; text-shadow: 2px 2px 4px rgba(0,0,0,0.5); }
                  ul { text-align: left; display: inline-block; }
                  li { margin: 10px 0; }
              </style>
          </head>
          <body>
              <div class="container">
                  <h1 class="success">🎉 DevOps Pipeline Success!</h1>
                  <p>Your infrastructure has been successfully deployed using:</p>
                  <ul>
                      <li>✅ Jenkins CI/CD Pipeline</li>
                      <li>✅ Terraform Infrastructure as Code</li>
                      <li>✅ Ansible Configuration Management</li>
                      <li>✅ Azure Cloud Platform</li>
                  </ul>
                  <p><strong>Deployment Date:</strong> {{ ansible_date_time.iso8601 }}</p>
                  <p><strong>Server:</strong> {{ inventory_hostname }}</p>
                  <p><strong>OS:</strong> {{ ansible_distribution }} {{ ansible_distribution_version }}</p>
                  <hr style="margin: 20px 0; border: 1px solid rgba(255,255,255,0.3);">
                  <p><em>🚀 Infrastructure as Code in Action!</em></p>
              </div>
          </body>
          </html>
        dest: /var/www/html/index.html
        owner: www-data
        group: www-data
        mode: '0644'
    
    - name: Ensure Apache is running and accessible
      systemd:
        name: apache2
        state: started
      
    - name: Check Apache status
      command: systemctl is-active apache2
      register: apache_status
      
    - name: Display Apache status
      debug:
        msg: "Apache status: {{ apache_status.stdout }}"
        
    - name: Test local web server
      uri:
        url: http://localhost
        method: GET
        status_code: 200
      retries: 5
      delay: 10
EOF
                            echo "✅ Created basic playbook, running it now..."
                            ansible-playbook -i inventory install_web.yml -v --timeout=300
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
                        echo "Waiting for web server to start..."
                        sleep time: 30, unit: 'SECONDS'

                        retry(15) {
                            script {
                                try {
                                    sh """
                                        echo "Testing connection to http://${publicIP}"
                                        curl -fs --connect-timeout 15 --max-time 30 http://${publicIP} > /dev/null
                                        echo '✅ Server is reachable!'
                                    """
                                } catch (Exception e) {
                                    echo "❌ Server not reachable yet, retrying in 10 seconds..."
                                    sleep time: 10, unit: 'SECONDS'
                                    throw e
                                }
                            }
                        }

                        sh """
                            echo "📄 Web page preview:"
                            curl -s --connect-timeout 15 --max-time 30 http://${publicIP} | head -30
                        """

                        writeFile file: 'deployment_url.txt', text: "http://${publicIP}"
                        archiveArtifacts artifacts: 'deployment_url.txt', fingerprint: true

                        echo "🎉 Web application successfully deployed at: http://${publicIP}"
                    }
                }
            }
        }
    }

    post {
        always {
            // Fixed: Remove the extra node block that was causing issues
            echo '🧹 Cleaning up temporary files...'
            sh 'rm -rf ${WORKSPACE}/.ssh'
        }
        success {
            script {
                if (fileExists('terraform/deployment_url.txt')) {
                    def url = readFile('terraform/deployment_url.txt').trim()
                    echo """
✅ DEPLOYMENT SUCCESSFUL!
🌍 URL: ${url}
📦 All stages completed successfully!
🚀 Infrastructure provisioned ✓
🔧 Web server installed ✓
🌐 Static site deployed ✓

Your DevOps pipeline is working perfectly! 🎉
                    """
                } else {
                    echo '✅ Pipeline completed successfully!'
                }
            }
        }
        failure {
            echo '''
❌ Pipeline failed. Check the specific stage that failed above.

Common solutions:
1. SSH Key Issues: Regenerate SSH key pair and update Jenkins credentials
2. Azure Permissions: Verify service principal has proper permissions
3. Network Issues: Check Azure NSG rules allow SSH (port 22) and HTTP (port 80)
4. VM Startup: Increase wait times for VM to fully boot
5. Credentials: Verify all Jenkins credentials are correctly configured

For SSH key issues specifically:
- Ensure private key format is correct (BEGIN/END PRIVATE KEY)
- Remove any Windows line endings from the key
- Verify the public key matches the private key
- Check that the public key is properly deployed to the Azure VM
            '''
        }
        cleanup {
            echo '🧼 Workspace cleanup complete.'
        }
    }
}