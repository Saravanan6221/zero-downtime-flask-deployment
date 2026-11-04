pipeline {
    agent any
    options { timestamps(); disableConcurrentBuilds() }
    parameters {
        choice(name: 'APP_VERSION', choices: ['v1', 'v2'], description: 'Application version to deploy')
        booleanParam(name: 'SIMULATE_FAILURE', defaultValue: false, description: 'Force candidate health check failure')
    }
    environment {
        DOCKERHUB_REPOSITORY = 'flask-bluegreen-demo'
        APP_HOST = 'REPLACE_WITH_APP_EC2_PUBLIC_IP'
    }
    stages {
        stage('Checkout') { steps { checkout scm } }
        stage('Validate') {
            steps {
                sh '''
                    set -e
                    test -f "$APP_VERSION/app.py"
                    test -f "$APP_VERSION/Dockerfile"
                    test -f "$APP_VERSION/requirements.txt"
                    python3 -m py_compile "$APP_VERSION/app.py"
                '''
            }
        }
        stage('Build and Push Image') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
                    sh '''
                        set -e
                        IMAGE="$DH_USER/$DOCKERHUB_REPOSITORY"
                        echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
                        docker build -t "$IMAGE:$BUILD_NUMBER" -t "$IMAGE:latest" -f "$APP_VERSION/Dockerfile" "$APP_VERSION"
                        docker push "$IMAGE:$BUILD_NUMBER"
                        docker push "$IMAGE:latest"
                        docker logout
                        echo "IMAGE=$IMAGE:$BUILD_NUMBER" > image.env
                    '''
                }
            }
        }
        stage('Deploy Candidate') {
            steps {
                script {
                    def imageName = readFile('image.env').trim().replace('IMAGE=', '')
                    withCredentials([sshUserPrivateKey(credentialsId: 'app-server-ssh', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                        sh """
                            set -e
                            test "$APP_HOST" != "REPLACE_WITH_APP_EC2_PUBLIC_IP"
                            chmod 600 "$SSH_KEY"
                            scp -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new scripts/deploy.sh "$SSH_USER@$APP_HOST:/tmp/deploy.sh"
                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$SSH_USER@$APP_HOST" "chmod +x /tmp/deploy.sh && sudo /tmp/deploy.sh '${imageName}' '${BUILD_NUMBER}' '${params.SIMULATE_FAILURE}'"
                        """
                    }
                }
            }
        }
        stage('Verify') {
            steps {
                sh '''
                    set -e
                    curl --fail --silent --show-error --max-time 10 "http://$APP_HOST/health"
                '''
            }
        }
    }
    post {
        always { sh 'docker image prune -f || true'; archiveArtifacts artifacts: 'image.env', allowEmptyArchive: true }
        success { echo 'Deployment completed successfully.' }
        failure { echo 'Pipeline failed. Review candidate health check and deployment logs.' }
    }
}
