pipeline {
    agent any

    environment {
        // We will define 'docker-hub-creds' in Jenkins UI later
        DOCKER_CREDS = credentials('docker-hub-creds')
        DOCKER_USER = 'YOUR_DOCKERHUB_USERNAME'
    }

    stages {
        stage('Checkout') {
            steps {
                // This checks out the code from the branch that triggered the build
                checkout scm
            }
        }

        stage('Build & Push Docker Images') {
            steps {
                script {
                    // List of all your services
                    def services = [
                        'api-gateway',
                        'users-service',
                        'articles-service',
                        'comments-service',
                        'favorites-service',
                        'follows-service',
                        'metrics-service'
                    ]

                    // Log in to Docker Hub and loop through services
                    docker.withRegistry('', 'docker-hub-creds') {
                        services.each { service ->
                            echo "--- Building ${service} ---"
                            // Build image: username/moleculer-conduit:latest
                            // Note: This assumes your Dockerfiles are in the root or setup correctly.
                            // Since you are using a monorepo structure, ensure the build context is correct.
                            // If you use one Dockerfile for everything, we build it once and retag it,
                            // OR if you have specific build args, we use them.
                            // For this lab, assuming standard build:
                            def customImage = docker.build("${DOCKER_USER}/moleculer-conduit:latest")

                            echo "--- Pushing ${service} ---"
                            customImage.push()
                        }
                    }
                }
            }
        }

        stage('Deploy to K3s') {
            steps {
                script {
                    echo '--- Deploying to Kubernetes ---'
                    sh '''
                        # Point to the kubeconfig we set up in main.tf
                        export KUBECONFIG=/var/lib/jenkins/.kube/config

                        # Apply Config & NATS first
                        kubectl apply -f config.yaml
                        kubectl apply -f nats.yaml

                        # Apply all Services
                        kubectl apply -f api-gateway.yaml
                        kubectl apply -f users-service.yaml
                        kubectl apply -f articles-service.yaml
                        kubectl apply -f comments-service.yaml
                        kubectl apply -f favorites-service.yaml
                        kubectl apply -f follows-service.yaml
                        kubectl apply -f metrics-service.yaml

                        # Force restart to pick up new images (since we use :latest)
                        kubectl rollout restart deployment/api-gateway
                        kubectl rollout restart deployment/users-service
                        kubectl rollout restart deployment/articles-service
                        kubectl rollout restart deployment/comments-service
                        kubectl rollout restart deployment/favorites-service
                        kubectl rollout restart deployment/follows-service
                        kubectl rollout restart deployment/metrics-service
                    '''
                }
            }
        }
    }
}