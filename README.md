# SIT753 Task 7.3HD - DevOps CI/CD Pipeline

This repository contains the complete Jenkins pipeline configuration and supporting scripts for **SIT753 Task 7.3HD (DevOps)** at Deakin University.

This pipeline automates the end-to-end lifecycle—from code checkout to monitoring, for a forked version of the **Intelligent IoT Data Management System**:
- **Application Repository (Fork):** [https://github.com/maguzman6/Intelligent-IoT-Data-Management](https://github.com/maguzman6/Intelligent-IoT-Data-Management)


1. **`Jenkinsfile`**: A complete, 7-stage declarative pipeline implementing:
   - **Stage 1: Build** - Multi-stage Docker builds for the Express backend and React/Vite frontend.
   - **Stage 2: Test** - Runs 91 automated tests (46 Node.js backend unit & PostgreSQL integration tests, 6 frontend client validation tests, and 39 Python Pytest contract regression tests).
   - **Stage 3: Code Quality** - Runs SonarCloud static analysis with defined thresholds.
   - **Stage 4: Security** - Tri-layer security scans (`npm audit`, `Bandit` SAST, and `Trivy` container scanning).
   - **Stage 5: Deploy** - Deploys containers to an isolated Docker network (`iot-net`) with automated database migration and health check validation.
   - **Stage 6: Release** - Creates immutable version tags for both backend and frontend images (`v1.0.${BUILD_NUMBER}`).
   - **Stage 7: Monitoring** - Launches cAdvisor, Prometheus, and Grafana for live telemetry.
2. **`simulate_incident.sh`**: A lightweight script to simulate an operational incident (traffic surge / DoS) to show live metric spikes across the monitoring tools.

To achieve a clean, working pipeline without modifying the core project code, here are the main technical decisions:

1. **Forked Repository & Sonar Configuration:**
   - The application code itself remains untouched. The only file added to the forked repository was `sonar-project.properties`. This allows SonarScanner to run with proper exclusions (ignoring build folders and `node_modules`) and evaluate quality gates accurately.
2. **Frontend Nginx Reverse Proxy:**
   - In Stage 1, the frontend Docker image is configured with Nginx to serve the static React build and reverse-proxy `/api/` calls directly to the backend container. This ensures login and API requests work seamlessly without CORS or port conflicts.
3. **Database Integration Testing:**
   - Some integration tests require a live PostgreSQL database. The pipeline dynamically starts a temporary `test-db` container in Stage 2, runs all integration tests, and cleanly removes it in the `post` cleanup block so no leftover resources remain.
4. **Local Deployment vs. Remote Registry:**
   - For this assessment, the application is deployed locally using Docker containers on a private bridge network (`iot-net`).
   - The **Release** stage tags both verified images locally (`intelligent-iot-backend:v1.0.${BUILD_NUMBER}` and `intelligent-iot-frontend:v1.0.${BUILD_NUMBER}`). In a production environment, this exact same stage would be configured to run `docker push` to an external registry (like Docker Hub, AWS ECR, or GitHub Packages) to trigger cloud deployments.
5. **Secrets & Security:**
   - No passwords or tokens are stored in this repository or in plaintext `.env` files. Everything is pulled from the Jenkins Credential Store, and shell commands use single quotes to avoid Groovy string interpolation risks.

If running locally with Jenkins and Docker:

| Service | Local URL |
| :--- | :--- |
| **Jenkins** | `http://localhost:8080` | Pipeline job |
| **Frontend Web App** | `http://localhost:3000` |
| **cAdvisor Telemetry** | `http://localhost:8085` |
| **Prometheus** | `http://localhost:9090` |
| **Grafana** | `http://localhost:3001` |

To simulate an incident during monitoring:
```bash
./simulate_incident.sh
```
This sends a burst of requests to demonstrate real-time CPU and network spikes on cAdvisor, Prometheus, and Grafana.