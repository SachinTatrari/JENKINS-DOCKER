Command			What it does
docker-compose up		Builds (if needed) and starts the containers
docker-compose up -d		Same as above, but in the background
docker-compose up --build		Forces image rebuild, then starts containers
docker-compose up -d --build		Rebuilds images and starts containers in the background 

docker exec -xyz : Command to run the given commands within the running container
Ex: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword


------------------------------
Problem Encountered: Created a freestyle project in Jenkins which is pulling the github repo that runs node and does the testing of the code.
So the command which I gave as a build steps to execute in shell were:
npm install
npm run lint
npm test
Since this is what is required for my github project to run the app and for testing.

But build got failed saying the npm command not found. The issue was Jenkins container is not aware about the npm command since node is not installed 
in that particular container.

Solution:
Quick Fix		Install Node.js manually inside Jenkins container (not ideal)
Best Practice	Use a node:18 Docker image as the agent in your pipeline

---------------------------------
So, for instance you have Jenkins container running from the docker. And your Jenkinsfile has some commands which are related to docker such as docker compose up --build. Before pushing the Jenkinsfile 
up, you need to check if the Jenkins container has docker installed/working in it. To check that, you did this in your jenkins container terminal:
docker exec -it <jenkins_container_id> docker version.

if it errors out saying:
 OCI runtime exec failed: exec failed: unable to start container process: exec: "docker": executable file not found in $PATH: unknown

Means the jenkins container doesn't know about the docker. So you need the following steps:

Option 1: Mount Host Docker Socket (Most Common for Local Dev)

This lets the Jenkins container use your host’s Docker engine.
docker run -d \
  --name jenkins \
  -p 8080:8080 -p 50000:50000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts

IMP: -v /var/run/docker.sock:/var/run/docker.sock:
Mounts the Docker daemon socket file from your host into the container, so the container can send commands to your host’s Docker engine.

Part					Purpose
-p 8080:8080				Web UI access
-p 50000:50000				Jenkins agent communication(Master and Slave)
-v /var/run/docker.sock:/var/run/docker.sock	Give Jenkins access to host's Docker
-v jenkins_home:/var/jenkins_home		Persist Jenkins data(This is a named Docker volume (jenkins_home) being mounted to /var/jenkins_home inside the container.). Stores all of its config, plugins, jobs, and data
jenkins/jenkins:lts				Run stable Jenkins image




----
Then install the Docker CLI inside the Jenkins container so it can talk to the host's Docker engine:

docker exec -it jenkins apt-get update
docker exec -it jenkins apt-get install -y docker.io

Option 2: Use Docker-in-Docker (DinD)
More complex. Jenkins runs with its own Docker daemon inside the container.

This is useful for isolated CI/CD but is harder to manage and less secure.

------------------Security Note
Mounting the Docker socket (/var/run/docker.sock) gives the Jenkins container full control of your host system. Don't use it in production without caution.
-------------------

----------------------------------------------
Fixing the root permissions issue:
When I was trying to do :
docker exec -it jenkins apt-get update
docker exec -it jenkins apt-get install -y docker.io

system was saying you don't have root admin user permissions. For that we needed another Dockerfile which would provide us the root permissions and allow us to install CLI in our jenkins container to 
run docker inside it.
----
Sample Dockerfile:
FROM jenkins/jenkins:lts

USER root

RUN apt-get update && \
    apt-get install -y docker.io docker-compose && \
    apt-get clean

USER jenkins
----

Sample docker-compose.yml file:
version: '3.8'

services:
  jenkins:
    build:
      context: .             # Build from Dockerfile in current folder
    container_name: jenkins
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock  # Required for Jenkins to access Docker
    restart: unless-stopped

volumes:
  jenkins_home:


Here the context . will search the current folder and find the Dockerfile to do the build.
Now after having those  2 files, I did docker compose up --build -d.. It ran fine and image was built with root permissions.
Now I tried doing docker exec -it <containername> docker version.....It showed me version initially but down the line it said permission denied for the socket. 
Error: 
permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Get "http://%2Fvar%2Frun%2Fdocker.sock/v1.24/version": 
dial unix /var/run/docker.sock: connect: permission denied

Solution: Add Jenkins User to Docker Group Inside Container (Best)

First, get into the container as root:
docker exec -u 0 -it jenkins(container name here) bash

Inside the container, check if the docker group exists (usually does):
getent group docker

If it doesn’t, create it:
groupadd docker

Now, add the jenkins user to the docker group:
usermod -aG docker jenkins(container name here)

Exit the container:
exit

Restart the container:
docker restart jenkins

