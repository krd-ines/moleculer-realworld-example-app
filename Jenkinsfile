pipeline {
    agent any

    triggers {
        pollSCM('*/2 * * * *')
    }

    environment {
        // Credentials
        DOCKER_CREDS = credentials('docker-hub-creds')
        DOCKER_USER = 'mariaboukhelfa2025'
        IMAGE_NAME = "${DOCKER_USER}/moleculer-conduit:latest"
        KUBECONFIG = '/var/lib/jenkins/.kube/config'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                script {
                    docker.withRegistry('', 'docker-hub-creds') {
                        echo "--- Building Docker Image: ${IMAGE_NAME} ---"
                        def customImage = docker.build(IMAGE_NAME)

                        echo "--- Pushing to Docker Hub ---"
                        customImage.push()
                    }
                }
            }
        }

        // ❌ DELETED: "Deploy Monitoring Stack" stage is gone.
        // We now rely on the External Grafana Server (Terraform) instead.

        stage('Deploy to K3s') {
            steps {
                script {
                    echo '--- Deploying to Kubernetes ---'

                    def services = [
                        'api-gateway',
                        'users-service',
                        'articles-service',
                        'comments-service',
                        'favorites-service',
                        'follows-service',
                        'metrics-service'
                    ]

                    // Apply configs and NATS messaging
                    sh 'kubectl apply -f k8s/config.yaml'
                    sh 'kubectl apply -f k8s/nats.yaml'

                    // Wait for NATS to prevent connection errors
                    sh 'kubectl wait --for=condition=ready pod -l app=nats --timeout=60s || true'

                    // Deploy microservices
                    services.each { service ->
                        echo "--- Deploying ${service} ---"
                        sh "kubectl apply -f k8s/${service}.yaml"
                        // Force restart to pull the new image we just built
                        sh "kubectl rollout restart deployment/${service}"
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    echo '--- Verifying Deployments ---'
                    sh 'kubectl get pods -n default'
                    sh 'kubectl top nodes || echo "Metrics not ready yet"'
                }
            }
        }
    }

    post {
        success {
            echo '✅ Deployment successful!'
            echo '---------------------------------------------------'
            echo '🌍 App is running on the Master Node.'
            echo '📊 Monitoring is handled by your External Grafana Server.'
            echo '---------------------------------------------------'
        }
        failure {
            echo '❌ Deployment failed. Check logs above.'
        }
    }
}