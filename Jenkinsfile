pipeline {
  agent none

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    // PLACEHOLDER: replace with the real ECR/registry repository.
    IMAGE_REPOSITORY = '111111111111.dkr.ecr.eu-west-1.amazonaws.com/aeon/api'
    GITOPS_DEV_OVERLAY = 'gitops/overlays/dev'
  }

  stages {
    stage('Checkout') {
      agent { label 'linux' }
      steps {
        checkout scm
        script {
          env.IMAGE_TAG = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
          env.IMAGE_REF = "${env.IMAGE_REPOSITORY}:${env.IMAGE_TAG}"
        }
        stash name: 'source', includes: '**', excludes: '.venv/**,.git/**'
      }
    }

    stage('Unit tests') {
      agent {
        docker {
          image 'python:3.12-slim-bookworm'
          args '-u root:root'
        }
      }
      steps {
        unstash 'source'
        sh '''
          set -eu
          python -m venv /tmp/venv
          . /tmp/venv/bin/activate
          pip install --upgrade pip
          pip install -r requirements-dev.txt
          pytest -q
        '''
      }
    }

    stage('Build image') {
      agent {
        kubernetes {
          defaultContainer 'kaniko'
          yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-kaniko
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
  containers:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: ["sleep"]
      args: ["99d"]
      resources:
        requests:
          cpu: 250m
          memory: 512Mi
        limits:
          cpu: "1"
          memory: 2Gi
'''
        }
      }
      steps {
        container('kaniko') {
          unstash 'source'
          // Kaniko builds without a Docker daemon. The tarball is scanned
          // before anything is pushed.
          sh '''
            set -eu
            /kaniko/executor \
              --context="${PWD}" \
              --dockerfile="${PWD}/Dockerfile" \
              --destination="${IMAGE_REF}" \
              --tar-path="${PWD}/image.tar" \
              --no-push \
              --snapshot-mode=redo \
              --use-new-run
          '''
          stash name: 'image', includes: 'image.tar'
        }
      }
    }

    stage('Scan image') {
      agent { label 'linux' }
      steps {
        unstash 'image'
        sh '''
          set -eu
          trivy image \
            --input image.tar \
            --severity HIGH,CRITICAL \
            --exit-code 1 \
            --ignore-unfixed \
            --no-progress
        '''
      }
    }

    stage('Push image') {
      when {
        anyOf { branch 'main'; branch 'master' }
      }
      agent {
        kubernetes {
          defaultContainer 'crane'
          yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-kaniko
  containers:
    - name: crane
      image: gcr.io/go-containerregistry/crane:debug
      command: ["sleep"]
      args: ["99d"]
'''
        }
      }
      steps {
        container('crane') {
          unstash 'image'
          // PLACEHOLDER: crane authenticates via the ServiceAccount (IRSA)
          // or a Docker config mounted from a Jenkins credential, never plaintext.
          sh '''
            set -eu
            crane push image.tar "${IMAGE_REF}"
          '''
        }
      }
    }

    stage('Update GitOps (dev)') {
      when {
        anyOf { branch 'main'; branch 'master' }
      }
      agent { label 'linux' }
      steps {
        checkout scm
        withCredentials([
          usernamePassword(
            credentialsId: 'gitops-bot',
            usernameVariable: 'GIT_USERNAME',
            passwordVariable: 'GIT_TOKEN'
          )
        ]) {
          sh '''
            set -eu
            export IMAGE_REPOSITORY IMAGE_TAG GITOPS_DEV_OVERLAY
            ./ci/update-gitops.sh
          '''
        }
      }
    }
  }

  post {
    failure {
      echo 'A required check failed. The image was not pushed and GitOps was not updated.'
    }
  }
}
