FROM jenkins/jenkins:lts

USER root

# Add jenkins user to root group (GID 0) to access docker.sock
RUN usermod -aG root jenkins \
    && apt-get update \
    && apt-get install -y docker.io docker-compose \
    && apt-get clean

USER jenkins
