pipeline { 
    agent { label 'built-in' }

    environment {
        // Azure credentials
        ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ARM_CLIENT_ID = credentials('azure-client-id')
        ARM_CLIENT_SECRET = credentials('azure-client-secret')
        ARM_TENANT_ID = credentials('azure-tenant-id')
        
        // SSH key path
        SSH_KEY_PATH = "${WORKSPACE}/.ssh/azure-vm-key"
    }

    stages {
        stage('Checkout') {
            steps {
                echo '📦 Checking out code from Git repository...'
                checkout scm
            }
        }

        stage('Setup SSH Keys') {
            steps {
                echo '🔑 Setting up SSH keys...'
                script {
                    // Create .ssh directory
                    sh 'mkdir -p ${WORKSPACE}/.ssh'
                    sh 'chmod 700 ${WORKSPACE}/.ssh'
                    
                    // Extract SSH keys from Jenkins credentials
                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: 'ssh-private-key',
                            keyFileVariable: 'SSH_PRIVATE_KEY_FILE',
                            usernameVariable: 'SSH_USER'
                        ),
                        string(credentialsId: 'ssh-public-key', variable: 'SSH_PUBLIC_KEY')
                    ]) {
                        // Copy private key
                        sh '''
                            cp "${SSH_PRIVATE_KEY_FILE}" "${SSH_KEY_PATH}"
                            chmod 600 "${SSH_KEY_PATH}"
                            
                            # Verify key format
                            echo "Private key format check:"
                            head -1 "${SSH_KEY_PATH}"
                            tail -1 "${SSH_KEY_PATH}"
                            
                            # Create public key file for reference
                            echo "${SSH_PUBLIC_KEY}" > "${SSH_KEY_PATH}.pub"
                            chmod 644 "${SSH_KEY_PATH}.pub"
                        '''
                    }
                }
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
                    withCredentials([string(credentialsId: 'ssh-public-key', variable: 'SSH_PUBLIC_KEY')]) {
                        sh '''
                            terraform plan -out=tfplan -var="ssh_public_key=${SSH_PUBLIC_KEY}"
                        '''
                    }
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    echo '🚀 Applying Terraform configuration...'
                    withCredentials([string(credentialsId: 'ssh-public-key', variable: 'SSH_PUBLIC_KEY')]) {
                        sh '''
                            terraform apply -auto-approve -var="ssh_public_key=${SSH_PUBLIC_KEY}" tfplan
                        '''
                    }
                }
            }
        }

        stage('Wait for VM Initialization') {
            steps {
                echo '⏳ Waiting for VM to fully initialize...'
                script {
                    // Get public IP
                    def publicIP = ""
                    dir('terraform') {
                        publicIP = sh(
                            script: "terraform output -raw public_ip_address",
                            returnStdout: true
                        ).trim()
                    }
                    
                    echo "VM Public IP: ${publicIP}"
                    
                    // Wait for SSH service to be ready
                    echo "Waiting for SSH service to be ready..."
                    def sshReady = false
                    def maxAttempts = 20
                    
                    for (int i = 1; i <= maxAttempts; i++) {
                        try {
                            sh "timeout 10 nc -zv ${publicIP} 22"
                            sshReady = true
                            echo "✅ SSH service is ready after ${i} attempts"
                            break
                        } catch (Exception e) {
                            echo "SSH attempt ${i}/${maxAttempts} failed, waiting 15 seconds..."
                            sleep 15
                        }
                    }
                    
                    if (!sshReady) {
                        error "SSH service not ready after ${maxAttempts} attempts"
                    }
                    
                    // Additional wait for VM to fully boot
                    echo "Waiting additional 30 seconds for VM to fully boot..."
                    sleep 30
                }
            }
        }

        stage('Test SSH Connection') {
            steps {
                echo '🔍 Testing SSH connection...'
                script {
                    def publicIP = ""
                    dir('terraform') {
                        publicIP = sh(
                            script: "terraform output -raw public_ip_address",
                            returnStdout: true
                        ).trim()
                    }
                    
                    // Test SSH connection with proper error handling
                    def sshWorking = false
                    def maxAttempts = 10
                    
                    for (int i = 1; i <= maxAttempts; i++) {
                        try {
                            sh """
                                ssh -i "${SSH_KEY_PATH}" \
                                    -o StrictHostKeyChecking=no \
                                    -o UserKnownHostsFile=/dev/null \
                                    -o ConnectTimeout=30 \
                                    -o BatchMode=yes \
                                    -o LogLevel=ERROR \
                                    azureuser@${publicIP} 'echo "SSH connection successful!"'
                            """
                            sshWorking = true
                            echo "✅ SSH connection established after ${i} attempts"
                            break
                        } catch (Exception e) {
                            echo "SSH test attempt ${i}/${maxAttempts} failed"
                            if (i == maxAttempts) {
                                // Show verbose output for debugging
                                sh """
                                    echo "Final SSH attempt with verbose output:"
                                    ssh -i "${SSH_KEY_PATH}" \
                                        -o StrictHostKeyChecking=no \
                                        -o UserKnownHostsFile=/dev/null \
                                        -o ConnectTimeout=30 \
                                        -vvv azureuser@${publicIP} 'echo "test"' 2>&1 | head -20 || true
                                """
                                error "SSH connection failed after ${maxAttempts} attempts"
                            } else {
                                sleep 15
                            }
                        }
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
${publicIP} ansible_user=azureuser ansible_ssh_private_key_file=${SSH_KEY_PATH} ansible_host_key_checking=false ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30'

[all:vars]
ansible_python_interpreter=/usr/bin/python3
"""

                        echo "Inventory file created:"
                        sh 'cat ../ansible/inventory'
                    }
                }
            }
        }

        stage('Test Ansible Connection') {
            steps {
                dir('ansible') {
                    echo '🔗 Testing Ansible connection...'
                    retry(5) {
                        sh '''
                            echo "Testing Ansible ping..."
                            ansible webservers -i inventory -m ping -v --timeout=60
                        '''
                    }
                }
            }
        }

        stage('Install Web Server') {
            steps {
                dir('ansible') {
                    echo '🛠️ Installing Apache web server via Ansible...'
                    script {
                        // Create playbook if it doesn't exist
                        if (!fileExists('install_web.yml')) {
                            writeFile file: 'install_web.yml', text: '''---
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
'''
                        }
                        
                        // Run playbook
                        sh 'ansible-playbook -i inventory install_web.yml -v --timeout=300'
                    }
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
            echo '🧹 Cleaning up temporary files...'
            sh 'rm -rf ${WORKSPACE}/.ssh || true'
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
            '''
        }
        cleanup {
            echo '🧼 Workspace cleanup complete.'
        }
    }
}