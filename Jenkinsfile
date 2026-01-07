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

                    sh 'kubectl apply -f config.yaml'
                    sh 'kubectl apply -f nats.yaml'


                    services.each { service ->
                        echo "--- Deploying ${service} ---"
                        sh "kubectl apply -f ${service}.yaml"


                        sh "kubectl rollout restart deployment/${service}"
                    }
                }
            }
        }
    }
}