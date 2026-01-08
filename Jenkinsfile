pipeline {
    agent any


    triggers {
        pollSCM('*/2 * * * *')
    }

    environment {

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

                        def customImage = docker.build(IMAGE_NAME)

                        echo "--- Pushing to Docker Hub ---"
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
                    
                    // Deploy monitoring (idempotent - safe to run every time)
                    sh 'kubectl apply -f k8s/monitoring/namespace.yaml'
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

                    sh 'kubectl apply -f k8s/config.yaml'
                    sh 'kubectl apply -f k8s/nats.yaml'


                    services.each { service ->
                        echo "--- Deploying ${service} ---"
                        sh "kubectl apply -f k8s/${service}.yaml"


                        sh "kubectl rollout restart deployment/${service}"
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    echo '--- Verifying Deployments ---'
                    sh 'kubectl get pods -n monitoring'
                    sh 'kubectl get pods -n default'
                }
            }
        }
    }

    post {
        success {
            echo '✅ Deployment successful!'
            echo "Prometheus: http://<master-ip>:30090"
            echo "Grafana: http://<master-ip>:30030 (admin/admin123)"
        }
        failure {
            echo '❌ Deployment failed. Check logs above.'
        }
    }
}