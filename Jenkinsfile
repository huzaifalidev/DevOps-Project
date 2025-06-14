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
        
        # ... rest of your pipeline stages
    }
    
    post {
        always {
            // Clean up any temporary files that might contain credentials
            sh '''
                # Remove any temporary credential files
                find . -name "*.tfvars" -delete 2>/dev/null || true
                find . -name ".terraform*" -type f -delete 2>/dev/null || true
            '''
        }
    }
}