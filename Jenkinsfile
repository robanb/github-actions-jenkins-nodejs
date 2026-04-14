// Jenkinsfile — declarative CI pipeline for github-actions-jenkins-nodejs.
//
// Mirrors .github/workflows/ci.yml stage-for-stage on the same codebase
// so the two tools can be compared side-by-side. See docs/JENKINS.md for
// the detailed walkthrough and the local Jenkins LTS bring-up.
//
// Stages: Checkout -> Lint -> Test (Node 18) -> Test (Node 20) -> Archive
//
// The two test stages run sequentially on purpose: it keeps the file
// simple, avoids workspace contention between parallel npm installs, and
// is fast enough for a teaching lab. See the "Extending the pipeline"
// section of docs/JENKINS.md for a parallel variant.

pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    timeout(time: 15, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }

  triggers {
    // Local Jenkins has no inbound webhook, so poll the remote.
    pollSCM('H/5 * * * *')
  }

  environment {
    CI = 'true'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Lint') {
      tools { nodejs 'Node 20' }
      steps {
        sh 'node --version'
        sh 'npm ci'
        sh 'npm run lint'
      }
    }

    stage('Test (Node 18)') {
      tools { nodejs 'Node 18' }
      steps {
        sh 'node --version'
        sh 'npm ci'
        sh 'npm run test:coverage -- --ci'
      }
      post {
        always {
          junit 'reports/junit/junit.xml'
        }
      }
    }

    stage('Test (Node 20)') {
      tools { nodejs 'Node 20' }
      steps {
        sh 'node --version'
        sh 'npm ci'
        sh 'npm run test:coverage -- --ci'
      }
      post {
        always {
          junit 'reports/junit/junit.xml'
        }
        success {
          archiveArtifacts artifacts: 'coverage/**', fingerprint: true
        }
      }
    }
  }

  post {
    success { echo 'Pipeline succeeded.' }
    failure { echo 'Pipeline failed — check the Console Output and Test Result pages.' }
    always  { cleanWs(notFailBuild: true) }
  }
}
