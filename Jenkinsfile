# Zero-Downtime Deployment – Corrected Jenkinsfile

```groovy
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
            description: 'Select the Flask application version to deploy'
        )

        booleanParam(
            name: 'SIMULATE_FAILURE',
            defaultValue: false,
            description: 'Simulate candidate health check failure to test rollback'
        )
    }

    environment {
        DOCKERHUB_REPOSITORY = 'flask-bluegreen-demo'
        APP_HOST = '3.239.220.63'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Checking out application source code from GitHub...'
                checkout scm
            }
        }

        stage('Validate') {
            steps {
                sh '''
                    set -eu

                    case "$APP_VERSION" in
                        v1)
                            APP_DIR="version1"
                            ;;
                        v2)
                            APP_DIR="version2"
                            ;;
                        *)
                            echo "ERROR: Invalid application version"
                            exit 1
                            ;;
                    esac

                    echo "Validating application directory: $APP_DIR"

                    test -f "$APP_DIR/app.py"
                    test -f "$APP_DIR/Dockerfile"
                    test -f "$APP_DIR/requirements.txt"

                    python3 -m py_compile "$APP_DIR/app.py"

                    echo "Application validation successful"
                '''
            }
        }

        stage('Build and Push Image') {
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

                        case "$APP_VERSION" in
                            v1)
                                APP_DIR="version1"
                                ;;
                            v2)
                                APP_DIR="version2"
                                ;;
                        esac

                        IMAGE="$DH_USER/$DOCKERHUB_REPOSITORY"

                        echo "Logging in to Docker Hub..."

                        echo "$DH_TOKEN" | docker login \
                            --username "$DH_USER" \
                            --password-stdin

                        echo "Building Docker image..."

                        docker build \
                            --pull \
                            -t "$IMAGE:$BUILD_NUMBER" \
                            -t "$IMAGE:latest" \
                            -f "$APP_DIR/Dockerfile" \
                            "$APP_DIR"

                        echo "Pushing versioned Docker image..."

                        docker push "$IMAGE:$BUILD_NUMBER"

                        echo "Pushing latest Docker image..."

                        docker push "$IMAGE:latest"

                        docker logout

                        echo "IMAGE=$IMAGE:$BUILD_NUMBER" > image.env

                        echo "Docker image built and pushed successfully"
                   
