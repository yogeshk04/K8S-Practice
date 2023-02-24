pipeline {

    agent any

    environment{
        DOCKERHUB_USERNAME= "yogeshk04"
        APP_NAME= "argocd-py-app"
        IMAGE_TAG= "${BUILD_NUMBER}"
        IMAGE_NAME= "${DOCKERHUB_USERNAME}" + "/" + "${APP_NAME}"
        REGISTRY_CREDS= 'dockerhub'
    }

    stages{
        stage('Cleanup WS'){

            steps{
                script{
                    cleanWs()
                }
            }
        }

        stage('Git Checkout'){

            steps{
                script{
                    git credentialsId: 'github',
                    url: 'https://github.com/yogeshk04/argocd-project.git',
                    branch: 'master'
                }
            }                
        }

        stage('Build Docker Image'){
            steps{
                script{
                    docker_image = docker.build "${IMAGE_NAME}"
                }
            }
        }

        stage('Push Docker Image'){
            steps{
                script{
                    docker.withRegistry('', REGISTRY_CREDS){
                        docker_image.push("$BUILD_NUMBER")
                        docker_image.push('latest')
                    }
                }
            }
        }
        stage('Delete Docker images'){
            steps{
                script{
                    sh "docker rmi ${IMAGE_NAME}:${IMAGE_TAG}"
                    sh "docker rmi ${IMAGE_NAME}:latest"
                }
            }
        }
        stage('Update k8s deployment file'){
            steps{
                script{
                    sh """
                    cat deployment.yaml
                    sed -i 's/${APP_NAME}.*/${APP_NAME}:${IMAGE_TAG}/g' deployment.yaml
                    cat deployment.yaml
                    """
                }
            }
        }
        stage('Push deployment file to Git'){
            steps{
                script{
                    sh """
                        git config --global user.name "yogeshk04"
                        git config --global user.email "yogeshk04@gmail.com"
                        git add deployment.yaml
                        git commit -m "Updated image version in deployment.yaml file"                        
                    """
                    withCredentials([gitUsernamePassword(credentialsId: 'github', gitToolName: 'Default')]) {
                    sh "git push https://github.com/yogeshk04/argocd-project.git master"
                    }
                }
            }
        }
    }
}