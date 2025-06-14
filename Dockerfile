FROM jenkins/jenkins:lts

USER root

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

USER jenkins
