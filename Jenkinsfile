
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
            description: 'Application version to deploy'
        )
        booleanParam(
            name: 'SIMULATE_FAILURE',
            defaultValue: false,
            description: 'Force candidate health check failure'
        )
    }

    environment {
        DOCKERHUB_REPOSITORY = 'flask-bluegreen-demo'
        APP_HOST = '3.239.220.63'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate') {
            steps {
                sh '''
                    set -e

                    if [ "$APP_VERSION" = "v1" ]; then
                        APP_DIR="version1"
                    elif [ "$APP_VERSION" = "v2" ]; then
                        APP_DIR="version2"
                    else
                        echo "Invalid application version"
                        exit 1
                    fi

                    echo "Validating $APP_DIR"

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
                        set -e

                        if [ "$APP_VERSION" = "v1" ]; then
                            APP_DIR="version1"
                        else
                            APP_DIR="version2"
                        fi

                        IMAGE="$DH_USER/$DOCKERHUB_REPOSITORY"

                        echo "$DH_TOKEN" | docker login \
                            -u "$DH_USER" --password-stdin

                        docker build \
                            -t "$IMAGE:$BUILD_NUMBER" \
                            -t "$IMAGE:latest" \
                            -f "$APP_DIR/Dockerfile" \
                            "$APP_DIR"

                        docker push "$IMAGE:$BUILD_NUMBER"
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
                                set -e

                                test -n "$APP_HOST"
                                test "$APP_HOST" != "3.239.220.63"

                                chmod 600 "$SSH_KEY"

                                scp -i "$SSH_KEY" \
                                    -o StrictHostKeyChecking=accept-new \
                                    scripts/deploy.sh \
                                    "$SSH_USER@$APP_HOST:/tmp/deploy.sh"

                                ssh -i "$SSH_KEY" \
                                    -o StrictHostKeyChecking=accept-new \
                                    "$SSH_USER@$APP_HOST" \
                                    "chmod +x /tmp/deploy.sh && sudo /tmp/deploy.sh '$IMAGE_NAME' '$BUILD_NUMBER' '$SIMULATE_FAILURE_VALUE'"

                                echo "Deployment script executed"
                            '''
                        }
                    }
                }
            }
        }

        stage('Verify') {
            steps {
                sh '''
                    set -e

                    echo "Checking application health..."

                    curl --fail --silent --show-error \
                        --max-time 10 \
                        "http://$APP_HOST/health"

                    echo "Application health check successful"
                '''
            }
        }
    }

    post {
        always {
            sh 'docker image prune -f || true'
            archiveArtifacts(
                artifacts: 'image.env',
                allowEmptyArchive: true
            )
        }

        success {
            echo 'Deployment completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Review the Jenkins console output and deployment logs.'
        }
    }
}
