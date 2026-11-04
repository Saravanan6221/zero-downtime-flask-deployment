# Zero-Downtime Flask Deployment and Rollback

## Objective
Demonstrate blue-green style deployment of Flask v1 and v2 using Jenkins, Docker, Nginx and AWS EC2. A candidate container is started on an inactive localhost port and health-checked before Nginx switches traffic. The previous container is retained for rollback.

> Lab limitation: this is a single application EC2 demonstration. Nginx reloads gracefully, but this is not equivalent to a highly available multi-instance production architecture.

## Architecture
- Jenkins EC2: checkout, syntax validation, Docker build and Docker Hub push.
- Application EC2: Docker containers bind to localhost ports 5001 and 5002; Nginx listens on port 80.
- Request path: Client -> Nginx :80 -> active Flask container :5001 or :5002.
- Never expose ports 5001 or 5002 in the application EC2 security group.

## Repository layout
- version1/: Flask 1.0.0 app, requirements and Dockerfile.
- version2/: Flask 2.0.0 app, requirements and Dockerfile.
- nginx/: reverse-proxy and initial upstream configuration.
- scripts/deploy.sh: candidate deployment, health check and traffic switch.
- scripts/rollback.sh: manual rollback to the previous running container.
- Jenkinsfile: parameterized CI/CD pipeline.

## Prerequisites
1. Two Ubuntu EC2 instances: Jenkins host and application host.
2. Jenkins host: Java 21, Jenkins, Docker, Git and Python 3.
3. Application host: Docker, Nginx and curl.
4. Docker Hub repository named flask-bluegreen-demo.
5. Jenkins credentials: dockerhub-creds (Docker Hub username and access token, username/password type) and app-server-ssh (SSH private key credential for the application EC2 user).
6. Set APP_HOST in the Jenkinsfile to the application EC2 public IP before running the pipeline.

## Application EC2 setup
Install Docker, Nginx and curl. Copy nginx/default.conf to /etc/nginx/conf.d/default.conf and nginx/active-upstream.conf to /etc/nginx/conf.d/active-upstream.conf. Ensure the default Nginx site does not conflict with this server block, then run:
```bash
sudo nginx -t
sudo systemctl enable --now nginx
sudo mkdir -p /opt/bluegreen
sudo chown ubuntu:ubuntu /opt/bluegreen
```
The pipeline copies scripts/deploy.sh to /tmp/deploy.sh and runs it with sudo. Copy scripts/rollback.sh to the app host as /tmp/rollback.sh when manual rollback is needed.

## Jenkins setup
1. Create a Pipeline job and select Pipeline script from SCM.
2. SCM: Git; repository: https://github.com/Saravanan6221/zero-downtime-flask-deployment.git.
3. Branch specifier: */main; Script Path: Jenkinsfile.
4. Ensure the Jenkins service account can use Docker, or use a dedicated build agent.
5. Add credentials using the exact IDs listed above.

## Deployment and test procedure
1. Run with APP_VERSION=v1 and SIMULATE_FAILURE=false. Initial deployment should serve version 1.0.0.
2. Run with APP_VERSION=v2 and SIMULATE_FAILURE=false. Candidate starts on the inactive port, passes its health check, and Nginx switches to it. The v1 container remains running.
3. Verify with curl http://APP_EC2_PUBLIC_IP/ and curl http://APP_EC2_PUBLIC_IP/health.
4. Run with SIMULATE_FAILURE=true to force candidate health-check failure. The current Nginx upstream should remain unchanged.
5. For manual rollback, copy scripts/rollback.sh to the app host as /tmp/rollback.sh and run sudo bash /tmp/rollback.sh.

## Security group guidance
- Jenkins EC2: TCP 22 from administrator IP; TCP 8080 from administrator IP (or a restricted access path).
- Application EC2: TCP 22 from Jenkins EC2 security group and administrator IP for maintenance; TCP 80 from intended client IP ranges.
- Do not create inbound rules for 5001 or 5002.
- Use a Docker Hub access token, not an account password. Never commit private keys or credentials.

## Evidence to capture
1. GitHub repository file list.
2. Jenkins successful v1 build and curl output showing version 1.0.0.
3. Jenkins successful v2 build and curl output showing version 2.0.0.
4. Docker container list showing both version containers retained after a successful switch.
5. Failed candidate build with SIMULATE_FAILURE=true.
6. Curl output confirming the active healthy version is still served after failed deployment.
7. Manual rollback output and final health-check response.

## Limitations and production improvements
This is a learning lab. Production deployments should use multiple application instances across Availability Zones, an AWS Application Load Balancer, target health checks and connection draining, immutable image digests, managed secrets, monitoring, and a tested rollback policy. Avoid mutable latest tags in production.
