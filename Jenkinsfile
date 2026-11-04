
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
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

        // Replace with your CURRENT Application EC2 public IPv4.
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

                        echo "Pushing versioned image..."

                        docker push "$IMAGE:$BUILD_NUMBER"

                        echo "Pushing latest image..."

                        docker push "$IMAGE:latest"

                        docker logout

                        echo "IMAGE=$IMAGE:$BUILD_NUMBER" > image.env

                        echo "Docker image built and pushed successfully"
                    '''
                }
            }
        }

        stage('Deploy Candidate') {
            steps {
                script {
                    def imageName = readFile('image.env')
                        .trim()
                        .replace('IMAGE=', '')

                    withEnv([
                        "IMAGE_NAME=${imageName}",
                        "SIMULATE_FAILURE_VALUE=${params.SIMULATE_FAILURE}"
                    ]) {
                        withCredentials([
                            sshUserPrivateKey(
                                credentialsId: 'app-server-ssh',
                                keyFileVariable: 'SSH_KEY',
                                usernameVariable: 'SSH_USER'
                            )
                        ]) {
                            sh '''
                                set -eu

                                echo "Validating Application EC2 configuration..."

                                test -n "$APP_HOST"

                                if [ "$APP_HOST" = "3.239.220.63" ]; then
                                    echo "ERROR: Configure the actual Application EC2 public IP in Jenkinsfile."
                                    exit 1
                                fi

                                chmod 600 "$SSH_KEY"

                                echo "Testing SSH connectivity..."

                                ssh -i "$SSH_KEY" \
                                    -o BatchMode=yes \
                                    -o ConnectTimeout=10 \
                                    -o StrictHostKeyChecking=accept-new \
                                    "$SSH_USER@$APP_HOST" \
                                    "echo SSH connection successful"

                                echo "Copying deployment script to Application EC2..."

                                scp -i "$SSH_KEY" \
                                    -o ConnectTimeout=10 \
                                    -o StrictHostKeyChecking=accept-new \
                                    scripts/deploy.sh \
                                    "$SSH_USER@$APP_HOST:/tmp/deploy.sh"

                                echo "Executing deployment script..."

                                ssh -i "$SSH_KEY" \
                                    -o ConnectTimeout=10 \
                                    -o StrictHostKeyChecking=accept-new \
                                    "$SSH_USER@$APP_HOST" \
                                    "chmod +x /tmp/deploy.sh && sudo /tmp/deploy.sh '$IMAGE_NAME' '$BUILD_NUMBER' '$SIMULATE_FAILURE_VALUE'"

                                echo "Deployment script executed successfully"
                            '''
                        }
                    }
                }
            }
        }

        stage('Verify') {
            steps {
                sh '''
                    set -eu

                    echo "Waiting for application to respond..."

                    ATTEMPTS=10
                    COUNT=0

                    until curl --fail --silent --show-error \
                        --max-time 5 \
                        "http://$APP_HOST/health"; do

                        COUNT=$((COUNT + 1))

                        if [ "$COUNT" -ge "$ATTEMPTS" ]; then
                            echo "ERROR: Application health verification failed"
                            exit 1
                        fi

                        echo "Health check attempt $COUNT failed. Retrying..."
                        sleep 3
                    done

                    echo ""
                    echo "Application health verification successful"
                '''
            }
        }
    }

    post {
        always {
            echo 'Performing Jenkins workspace cleanup...'

            sh '''
                docker image prune -f || true
            '''

            archiveArtifacts(
                artifacts: 'image.env',
                allowEmptyArchive: true
            )
        }

        success {
            echo 'SUCCESS: Deployment pipeline completed successfully.'
            echo 'Application health verification passed.'
        }

        failure {
            echo 'FAILURE: Pipeline execution failed.'
            echo 'Check the Jenkins console output and Application EC2 deployment logs.'
        }

        aborted {
            echo 'Pipeline execution was aborted.'
        }
    }
}
