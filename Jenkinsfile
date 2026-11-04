
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    parameters {
        choice(
            name: 'APP_VERSION',
            choices: ['v1', 'v2'],
            description: 'Select Flask application version'
        )

        booleanParam(
            name: 'SIMULATE_FAILURE',
            defaultValue: false,
            description: 'Simulate candidate application health-check failure'
        )
    }

    environment {
        DOCKERHUB_REPOSITORY = 'flask-bluegreen-demo'
        APP_HOST = '3.239.220.63'
        APP_USER = 'ubuntu'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Checking out source code from GitHub'

                checkout scm

                sh '''
                    echo "Repository files:"
                    ls -la
                '''
            }
        }

        stage('Validate') {
            steps {
                script {
                    if (params.APP_VERSION == 'v1') {
                        env.APP_DIR = 'version1'
                        env.EXPECTED_VERSION = '1.0.0'
                    } else {
                        env.APP_DIR = 'version2'
                        env.EXPECTED_VERSION = '2.0.0'
                    }

                    env.SIMULATE_FAILURE_VALUE =
                        params.SIMULATE_FAILURE ? 'true' : 'false'
                }

                sh '''
                    set -eu

                    echo "Selected application: $APP_DIR"
                    echo "Expected version: $EXPECTED_VERSION"

                    test -f "$APP_DIR/app.py"
                    test -f "$APP_DIR/Dockerfile"
                    test -f "$APP_DIR/requirements.txt"

                    test -f scripts/deploy.sh

                    python3 -m py_compile "$APP_DIR/app.py"

                    bash -n scripts/deploy.sh

                    echo "Application and deployment script validation passed"
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_TOKEN'
                    )
                ]) {
                    script {
                        env.IMAGE_NAME =
                            "${DH_USER}/${env.DOCKERHUB_REPOSITORY}:${env.BUILD_NUMBER}"

                        env.LATEST_IMAGE =
                            "${DH_USER}/${env.DOCKERHUB_REPOSITORY}:latest"
                    }

                    sh '''
                        set -eu

                        echo "Logging in to Docker Hub"

                        echo "$DH_TOKEN" | docker login \
                            --username "$DH_USER" \
                            --password-stdin

                        echo "Building Docker image"

                        docker build \
                            --pull \
                            -t "$IMAGE_NAME" \
                            -t "$LATEST_IMAGE" \
                            -f "$APP_DIR/Dockerfile" \
                            "$APP_DIR"

                        echo "Docker image built successfully"

                        docker image inspect "$IMAGE_NAME" >/dev/null

                        docker logout
                    '''
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_TOKEN'
                    )
                ]) {
                    sh '''
                        set -eu

                        echo "$DH_TOKEN" | docker login \
                            --username "$DH_USER" \
                            --password-stdin

                        echo "Pushing versioned image: $IMAGE_NAME"

                        docker push "$IMAGE_NAME"

                        echo "Updating latest image tag"

                        docker push "$LATEST_IMAGE"

                        docker logout

                        echo "Docker images pushed successfully"
                    '''
                }
            }
        }

        stage('Deploy to Application EC2') {
            steps {
                sshagent(credentials: ['app-server-ssh']) {
                    sh '''
                        set -eu

                        REMOTE_SCRIPT="/tmp/bluegreen-deploy-${BUILD_NUMBER}.sh"

                        echo "Copying deployment script to Application EC2"

                        scp \
                            -o StrictHostKeyChecking=no \
                            -o UserKnownHostsFile=/dev/null \
                            -o ConnectTimeout=10 \
                            scripts/deploy.sh \
                            "$APP_USER@$APP_HOST:$REMOTE_SCRIPT"

                        echo "Starting remote blue-green deployment"

                        ssh \
                            -o StrictHostKeyChecking=no \
                            -o UserKnownHostsFile=/dev/null \
                            -o ConnectTimeout=10 \
                            "$APP_USER@$APP_HOST" \
                            "sudo bash '$REMOTE_SCRIPT' '$IMAGE_NAME' '$BUILD_NUMBER' '$SIMULATE_FAILURE_VALUE'"

                        echo "Remote deployment script completed"
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    set -eu

                    echo "Checking application health through Nginx"

                    HEALTH_RESPONSE=$(curl \
                        --fail \
                        --silent \
                        --show-error \
                        --retry 10 \
                        --retry-delay 3 \
                        --retry-connrefused \
                        --max-time 5 \
                        "http://$APP_HOST/health")

                    echo "$HEALTH_RESPONSE"

                    echo "Checking application version"

                    APP_RESPONSE=$(curl \
                        --fail \
                        --silent \
                        --show-error \
                        --retry 5 \
                        --retry-delay 2 \
                        --retry-connrefused \
                        --max-time 5 \
                        "http://$APP_HOST/")

                    echo "$APP_RESPONSE"

                    printf '%s' "$APP_RESPONSE" |
                        grep -Eq "\\"version\\"[[:space:]]*:[[:space:]]*\\"$EXPECTED_VERSION\\""

                    echo "Application version verified: $EXPECTED_VERSION"
                    echo "Zero-downtime deployment verification passed"
                '''
            }
        }
    }

    post {
        success {
            echo """
            ==========================================
            DEPLOYMENT SUCCESSFUL
            ==========================================
            Application Version: ${params.APP_VERSION}
            Expected Version: ${env.EXPECTED_VERSION}
            Docker Image: ${env.IMAGE_NAME}
            Application Server: ${env.APP_HOST}
            ==========================================
            """
        }

        failure {
            echo """
            ==========================================
            DEPLOYMENT FAILED
            ==========================================
            Check the Jenkins Console Output.
            If candidate deployment failed, inspect
            the Application EC2 rollback logs.
            ==========================================
            """
        }

        always {
            archiveArtifacts(
                artifacts: 'image.env',
                allowEmptyArchive: true
            )

            echo 'Jenkins pipeline execution completed'
        }
    }
}
