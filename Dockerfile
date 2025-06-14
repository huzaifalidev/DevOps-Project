FROM jenkins/jenkins:lts

USER root

# Install required tools including ansible & terraform
RUN apt-get update && \
    apt-get install -y \
    python3 \
    python3-pip \
    curl \
    sudo \
    git \
    gnupg \
    software-properties-common && \
    apt-add-repository --yes --update ppa:ansible/ansible || true && \
    apt-get update && \
    apt-get install -y ansible && \
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && \
    apt-get install -y terraform

USER jenkins
