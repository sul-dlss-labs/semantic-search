// The same secrets bin/with-deploy-env loads for local deploys (see VAULT_SECRET_PATHS there), minus
// the "puppet/" prefix.
def secrets = [
    [path: 'application/semantic-search/demo/secret_key_base', secretValues: [
        [envVar: 'SECRET_KEY_BASE', vaultKey: 'content']]],
    [path: 'application/semantic-search/demo/litellm_key', secretValues: [
        [envVar: 'LITELLM_API_KEY', vaultKey: 'content']]]
]

pipeline {
  agent any

  environment {
    PROJECT = 'sul-dlss-labs/semantic-search'
    // Without explicit UTF-8, the Psych YAML library will run into encoding
    // mismatches and the build will explode.
    LANG = 'C.UTF-8'
    LC_ALL = 'C.UTF-8'
  }

  stages {
    stage('Deploy to demo on merges to main') {
      environment {
        DEPLOY_ENVIRONMENT = 'demo'
      }

      when {
        branch 'main'
      }

      steps {
        checkout scm

        dir('webapp') {
          withVault([vaultSecrets: secrets]) {
            sshagent (['sul-devops-team', 'sul-continuous-deployment']) {
              sh '''#!/bin/bash -l
                # Load application dependencies
                rvm use "$(cat .ruby-version)@semantic-search" --create
                gem install bundler
                bundle install

                # Deploy it
                bundle exec bin/kamal deploy
              '''
            }
          }
        }
      }

      // No slack messages for now.
      // post {
      //   always {
      //     build job: '/Continuous Deployment/Slack Deployment Notification', parameters: [
      //       string(name: 'PROJECT', value: env.PROJECT),
      //       string(name: 'GIT_COMMIT', value: env.GIT_COMMIT),
      //       string(name: 'GIT_URL', value: env.GIT_URL),
      //       string(name: 'GIT_PREVIOUS_SUCCESSFUL_COMMIT', value: env.GIT_PREVIOUS_SUCCESSFUL_COMMIT),
      //       string(name: 'DEPLOY_ENVIRONMENT', value: env.DEPLOY_ENVIRONMENT),
      //       string(name: 'TAG_NAME', value: env.TAG_NAME),
      //       booleanParam(name: 'SUCCESS', value: currentBuild.resultIsBetterOrEqualTo('SUCCESS')),
      //       string(name: 'RUN_DISPLAY_URL', value: env.RUN_DISPLAY_URL)
      //     ]
      //   }
      // }
    }
  }
}
