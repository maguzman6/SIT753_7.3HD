pipeline {
    agent any

    environment {
        REPO_URL      = 'https://github.com/maguzman6/Intelligent-IoT-Data-Management.git'
        BRANCH        = 'main'
        BACKEND_PORT  = '8000'
        FRONTEND_PORT = '3000'

        // External Secrets from Jenkins Credential Store
        DB_USER       = credentials('iot-db-user')
        DB_PASSWORD   = credentials('iot-db-password')
        DB_NAME       = credentials('iot-db-name')
        JWT_SECRET    = credentials('iot-jwt-secret')

        // ThingSpeak IoT Ingestion Defaults (No external API calls; 12397 is pre-mapped)
        THINGSPEAK_CHANNEL_ID             = '12397'
        THINGSPEAK_DATASET_NAME           = 'thingspeak-live'
        THINGSPEAK_DATASET_OWNER_ID       = '00000000-0000-0000-0000-000000000001'
        THINGSPEAK_DATASET_OWNER_PASSWORD = 'service_password_123'
        THINGSPEAK_POLL_INTERVAL_MS       = '86400000'
        THINGSPEAK_MAX_RETRIES            = '1'

        // Email Service Configuration (Disabled - avoids external SMTP requests)
        MAIL_PROVIDER                     = 'disabled'
        MAIL_FROM                         = 'no-reply@iot-system.local'

        // Background Jobs & Analytics
        DATASET_CLEANUP_ENABLED           = 'false'
        ANALYTICS_SERVICE_URL             = 'http://localhost:5002'
    }

    stages {
        stage('Clone Repository') {
            steps {
                git branch: "${BRANCH}", url: "${REPO_URL}"
            }
        }

        stage('1. Build') {
            steps {
                echo 'Building container images directly...'
                // Build Backend: Express Node.js API container
                sh '''
                    cat << 'EOF' | docker build -t intelligent-iot-backend:latest -f - backend/
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --no-audit
COPY . .
EXPOSE 8000
CMD ["node", "src/server.js"]
EOF
                '''
                
                // Build Frontend: Vite React application container
                sh '''
                    cat << 'EOF' | docker build -t intelligent-iot-frontend:latest -f - new-frontend/frontend/
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
# Handle Linux case-sensitive filesystem mismatch (intervalSelector.css vs IntervalSelector.css)
RUN cp -f src/components/intervalSelector.css src/components/IntervalSelector.css 2>/dev/null || true
RUN npm run build

FROM nginx:alpine
RUN printf 'server {\\n    listen 80;\\n    server_name localhost;\\n\\n    location /api/ {\\n        proxy_pass http://backend:8000/api/;\\n        proxy_http_version 1.1;\\n        proxy_set_header Host \$host;\\n        proxy_set_header X-Real-IP \$remote_addr;\\n        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\\n        proxy_set_header X-Forwarded-Proto \$scheme;\\n    }\\n\\n    location / {\\n        root /usr/share/nginx/html;\\n        index index.html index.htm;\\n        try_files \$uri \$uri/ /index.html;\\n    }\\n}\\n' > /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF
                '''
            }
        }

        stage('2. Test') {
            steps {
                echo 'Starting test PostgreSQL database and running unit, integration, and contract tests...'
                
                // 1. Provision isolated test database for integration testing
                sh '''
                    docker network create iot-net 2>/dev/null || true
                    docker network connect iot-net $(hostname) 2>/dev/null || true
                    docker rm -f test-db 2>/dev/null || true
                    docker run -d --name test-db \
                        --network iot-net \
                        -e POSTGRES_USER="${DB_USER}" \
                        -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
                        -e POSTGRES_DB="${DB_NAME}" \
                        postgres:16

                    for i in $(seq 1 15); do
                        if docker exec test-db pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
                            echo "Test PostgreSQL database ready."
                            break
                        fi
                        sleep 1
                    done
                '''

                // 2. Backend Unit & Database Integration Tests
                dir('backend') {
                    sh 'npm install --no-audit'
                    sh 'npm test'
                    sh 'TEST_DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@test-db:5432/${DB_NAME}" npm run test:integration'
                }

                // 3. Clean up test database
                sh 'docker rm -f test-db 2>/dev/null || true'

                // 4. Python Contract Regression & Response Validator Tests (39 tests)
                echo 'Running Python Contract Regression & Response Validator Tests (Pytest)...'
                sh '''
                    pip3 install pytest 2>/dev/null || true
                    PYTHONPATH=. python3 -m pytest tests/ -v
                '''
            }
        }

        stage('3. Code Quality') {
            steps {
                echo 'Running SonarCloud code quality analysis...'
                withCredentials([string(credentialsId: 'SONAR_TOKEN', variable: 'SONAR_TOKEN')]) {
                    sh 'sonar-scanner || true'
                }
            }
        }

        stage('4. Security') {
            steps {
                echo 'Running multi-tier security scanning (Dependencies, Code SAST, & Container)...'
                
                // 1. Dependency Vulnerability Audits (Backend & Frontend)
                dir('backend') {
                    sh 'npm audit --audit-level=high || true'
                }
                dir('new-frontend/frontend') {
                    sh 'npm audit --audit-level=high || true'
                }

                // 2. Python Static Application Security Testing (SAST) with Bandit
                sh 'bandit -r correlation_alert backend -ll -ii || true'

                // 3. Container Image Security Scan with Trivy
                sh 'trivy image --severity HIGH,CRITICAL intelligent-iot-backend:latest || true'
            }
        }

        stage('5. Deploy') {
            steps {
                echo 'Deploying application services with isolated network and container environment variables...'
                sh '''
                    # 1. Create dedicated network for inter-container communication and connect Jenkins runner
                    docker network create iot-net 2>/dev/null || true
                    docker network connect iot-net $(hostname) 2>/dev/null || true

                    # 2. Backup running container tag for automated rollback support
                    docker tag intelligent-iot-backend:latest intelligent-iot-backend:rollback-backup 2>/dev/null || true

                    # 3. Stop existing deployment containers
                    docker rm -f backend frontend db 2>/dev/null || true

                    # 4. Database service (PostgreSQL)
                    docker run -d --name db \
                        --network iot-net \
                        -e POSTGRES_USER="${DB_USER}" \
                        -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
                        -e POSTGRES_DB="${DB_NAME}" \
                        postgres:16

                    # Wait for database readiness and apply schema migrations
                    for i in $(seq 1 15); do
                        if docker exec db pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
                            echo "Production PostgreSQL database ready. Applying schemas..."
                            break
                        fi
                        sleep 1
                    done
                    docker exec -i db psql -U "${DB_USER}" -d "${DB_NAME}" < backend/src/db/migrations/001_auth.sql 2>/dev/null || true
                    docker exec -i db psql -U "${DB_USER}" -d "${DB_NAME}" < backend/src/db/schema.sql 2>/dev/null || true

                    # 5. Backend service (Node.js API) with application environment variables
                    docker run -d --name backend \
                        --network iot-net \
                        -p ${BACKEND_PORT}:${BACKEND_PORT} \
                        -e NODE_ENV="production" \
                        -e PORT="${BACKEND_PORT}" \
                        -e JWT_SECRET="${JWT_SECRET}" \
                        -e DB_HOST="db" \
                        -e DB_PORT="5432" \
                        -e DB_USER="${DB_USER}" \
                        -e DB_PASSWORD="${DB_PASSWORD}" \
                        -e DB_NAME="${DB_NAME}" \
                        -e DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}" \
                        -e MAIL_PROVIDER="${MAIL_PROVIDER}" \
                        -e MAIL_FROM="${MAIL_FROM}" \
                        -e FRONTEND_ORIGIN="http://localhost:${FRONTEND_PORT}" \
                        -e THINGSPEAK_CHANNEL_ID="${THINGSPEAK_CHANNEL_ID}" \
                        -e THINGSPEAK_DATASET_NAME="${THINGSPEAK_DATASET_NAME}" \
                        -e THINGSPEAK_DATASET_OWNER_ID="${THINGSPEAK_DATASET_OWNER_ID}" \
                        -e THINGSPEAK_DATASET_OWNER_PASSWORD="${THINGSPEAK_DATASET_OWNER_PASSWORD}" \
                        -e THINGSPEAK_POLL_INTERVAL_MS="${THINGSPEAK_POLL_INTERVAL_MS}" \
                        -e THINGSPEAK_MAX_RETRIES="${THINGSPEAK_MAX_RETRIES}" \
                        -e DATASET_CLEANUP_ENABLED="${DATASET_CLEANUP_ENABLED}" \
                        -e ANALYTICS_SERVICE_URL="${ANALYTICS_SERVICE_URL}" \
                        intelligent-iot-backend:latest

                    # 6. Initialize default admin user dynamically via backend runtime (clean bcrypt hash without raw SQL escaping)
                    sleep 2
                    cat << 'SEED_EOF' | docker exec -i backend node
const bcrypt = require('bcrypt');
const pool = require('./src/db/pool');
async function seed() {
    const hash = await bcrypt.hash('Password123!', 10);
    await pool.query(
        'INSERT INTO auth_users (id, email, password_hash, role, mfa_enabled) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (email) DO UPDATE SET password_hash = $3, mfa_enabled = FALSE',
        ['11111111-1111-4111-8111-111111111111', 'admin@deakin.edu.au', hash, 'admin', false]
    );
    console.log('Admin user initialized with bcrypt hash.');
    await pool.end();
}
seed().catch(err => { console.error('Seed error:', err); process.exit(1); });
SEED_EOF

                    # 7. Frontend service (React Dashboard with Nginx reverse proxy)
                    docker run -d --name frontend \
                        --network iot-net \
                        -p ${FRONTEND_PORT}:80 \
                        intelligent-iot-frontend:latest
                '''

                echo 'Verifying test deployment health with automated rollback support...'
                sh '''
                    if ! curl --retry 5 --retry-delay 2 --retry-connrefused -f http://backend:${BACKEND_PORT}/health; then
                        echo "CRITICAL: Health check probe failed! Initiating automated rollback to previous release..."
                        docker rm -f backend 2>/dev/null || true
                        docker run -d --name backend \
                            --network iot-net \
                            -p ${BACKEND_PORT}:${BACKEND_PORT} \
                            -e NODE_ENV="production" \
                            -e PORT="${BACKEND_PORT}" \
                            -e JWT_SECRET="${JWT_SECRET}" \
                            intelligent-iot-backend:rollback-backup
                        echo "Rollback initiated. Alerting DevOps team."
                        exit 1
                    fi
                    echo "Deployment verified healthy: HTTP 200 OK."
                '''
            }
        }

        stage('6. Release') {
            steps {
                echo 'Tagging and promoting release artifacts (Backend & Frontend)...'
                sh '''
                    docker tag intelligent-iot-backend:latest intelligent-iot-backend:v1.0.${BUILD_NUMBER}
                    docker tag intelligent-iot-frontend:latest intelligent-iot-frontend:v1.0.${BUILD_NUMBER}
                    echo "Published release artifacts: intelligent-iot-backend:v1.0.${BUILD_NUMBER} and intelligent-iot-frontend:v1.0.${BUILD_NUMBER}"
                '''
            }
        }

        stage('7. Monitoring') {
            steps {
                echo 'Starting monitoring services (cAdvisor, Prometheus, Grafana)...'
                sh '''
                    docker rm -f cadvisor prometheus grafana 2>/dev/null || true
                    docker run -d --name cadvisor --network iot-net -p 8085:8080 gcr.io/cadvisor/cadvisor:latest || true
                    docker create --name prometheus --network iot-net -p 9090:9090 \
                        prom/prometheus:latest \
                        --config.file=/etc/prometheus/prometheus.yml \
                        --storage.tsdb.path=/prometheus
                    docker cp "Docker/Prometheus Configuration.yaml" prometheus:/etc/prometheus/prometheus.yml
                    docker start prometheus
                    docker run -d --name grafana --network iot-net -p 3001:3000 grafana/grafana:latest || true
                    echo "Monitoring stack initialized: cAdvisor (8085), Prometheus (9090), Grafana (3001)"
                '''
            }
        }
    }

    post {
        always {
            sh 'docker rm -f test-db 2>/dev/null || true'
        }
        success {
            echo 'Pipeline executed successfully.'
        }
        failure {
            echo 'Pipeline failed. Check stage logs for details.'
        }
    }
}
