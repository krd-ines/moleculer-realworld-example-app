// app jenkines file hello
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
                        // Build the image
                        def customImage = docker.build(IMAGE_NAME)

                        echo "--- Pushing to Docker Hub ---"
                        // Push the image
                        customImage.push()
                    }
                }
            }
        }

        stage('Deploy Monitoring Stack') {
            steps {
                script {
                    echo '--- Deploying Monitoring Stack ---'
                    env.KUBECONFIG = '/var/lib/jenkins/.kube/config'

                    // --- FIX STARTS HERE ---
                    // We ignore the broken .yaml file from the repo and create the namespace manually.
                    // "|| true" ensures the build doesn't fail if the namespace already exists.
                    sh 'kubectl create namespace monitoring || true'
                    // -----------------------

                    // Deploy the rest of the monitoring stack
                    sh 'kubectl apply -f k8s/monitoring/prometheus-rbac.yaml'
                    sh 'kubectl apply -f k8s/monitoring/node-exporter.yaml'
                    sh 'kubectl apply -f k8s/monitoring/prometheus.yaml'
                    sh 'kubectl apply -f k8s/monitoring/grafana.yaml'
                }
            }
        }

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

                    env.KUBECONFIG = '/var/lib/jenkins/.kube/config'

                    // Apply configs and NATS messaging
                    sh 'kubectl apply -f k8s/config.yaml'
                    sh 'kubectl apply -f k8s/nats.yaml'

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
                    // Check if pods are running
                    sh 'kubectl get pods -n monitoring'
                    sh 'kubectl get pods -n default'
                }
            }
        }
    }

    post {
        success {
            echo '✅ Deployment successful!'
            // Note: Replace <master-ip> with your actual public IP in the output below
            echo "Prometheus is available at port 30090"
            echo "Grafana is available at port 30030 (login: admin/admin123)"
        }
        failure {
            echo '❌ Deployment failed. Check logs above.'
        }
    }
}