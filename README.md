# Open Ownership Register Exporter

This repository contains the code which exports the beneficial ownership
data stored in the OpenOwnership Register database. The input source is
a MongoDB database, with the data processed and mapped into a Gzipped
JSON-lines file, stored in S3.

The Exporter is written in Ruby, running using "Serverless" technologies.

The exporter is:
- orchestrated by AWS Step Functions
- uses S3 for temporary storage of processed parts
- uses S3 for storage of final output file
- uses AWS Athena (a serverless Presto implementation) to deduplicate and
  concatenate the output of small stages.
- uses DynamoDB to store metadata about which parts are completed or
  queued.
- uses SQS as a queueing system, both for processing parts and for
  extracting data from completed parts during the final export stage.

## Contents

- [Setting up local development](#setting-up-local-development)
- [Setting up the AWS Stack](#setting-up-aws-stack)
- [Code Deployment](#code-deployment)
- [Running an export](#running-an-export)
- [Running tests](#running-tests)
- [Code overview](#code-overview)

## Setting up local development

## Setting up the AWS Stack

The setup in AWS is almost fully automated, once the env files have been setup.

Note: Currently need an existing bucket to put the code in, this should be automated.

Note: Currently the scripts have been tested with Admin user access run from local
enviroment, but this should be restricted before adding into any sort of remote scripts. 

1. Create deployment .deploy.env file

Sample .deploy.env
```
AWS_REGION=eu-west-1
ACCESS_KEY_ID=
SECRET_ACCESS_KEY=
AWS_ACCOUNT_ID=
CODE_BUCKET=
CODE_PREFIX=code
REPO_NAME=openownership/register-files-combiner
```

- The code bucket should be an existing S3 bucket, in the same region you are deploying into.
- The AWS access key / secret access key should have admin access to your AWS account.

2. Create ENV file in deploy/envs

TODO


3. Create Stack

Choose an appropriate name for the stack.
This would usually be "dev", "staging", "prod" etc, but any alphanumeric names are fine.

```
bundle exec deploy/create_stack $STACK_NAME
bundle exec deploy/create_stack dev
```

TODO: Currently the dynamodb tables are deployed with provisioned capacity 1, which is
not enough when running a large export. These need to autoscale, but this has not been
added to the deployment script yet. If necessary, increase the capacities manually before
running the export.

## Code Deployment

1. Package up the code

```
bundle exec deploy/package_code $BRANCH
bundle exec deploy/package_code main
```

- The script only accepts BRANCH but in the future a git SHA would be more appropriate.
- This will clone a fresh copy, install dependencies, zip up, and upload final code to
  the S3 bucket defined in .deploy.env

Note: currently this is run locally and uses RVM to install and select the Ruby version.
This should be dockerized for simplicity.

2. Deploy code

Once the code has been packaged up and the stack has been created, the code will need to
be deployed to the stack.

This will update the Lambda environment and the code, but the rest of the settings will
remain unchanged.

```
bundle exec deploy/deploy_code $STACK_NAME $BRANCH $ENV_NAME
bundle exec deploy/deploy_code dev main dev 
```

- The STACK_NAME is the name provided when creating the stack
- The BRANCH is the name provided when packaging the code
- The ENV_NAME should match the name of the .json file in deploy/envs/{ENV_NAME}.json
  For example, deploy/envs/dev.json would have the name dev

## Running an export

Find the appropriate Step Function in the AWS console:

https://eu-west-1.console.aws.amazon.com/states/home?region=eu-west-1#/statemachines

(The Region may be different).

Click to see the state machine with the correct name.
Click "Start Execution".
Click "Start Execution" with empty parameters {}.

Wait for the function to complete (production currently takes about 1 hour to export the 27 million records).
The results will be written in two places:

- In {S3_BUCKET} path bods_exports_results/{EXPORT_ID}.jsonl.gz
- In {S3_BUCKET} path bods_exports_results/export_parts/export={EXPORT_ID}/partX.jsonl.gz

The latter is both used when creating the final output file, but also is useful when looking at the data,
as downloading and unzipping the full file can be unwieldly.

## Running tests

There is no CI/CD currently active for this project.

To run tests locally, use the provided .test.env file, altering the mongo address if
necessary.

```
BODS_EXPORT_S3_BUCKET_NAME=
BODS_EXPORT_AWS_ACCESS_KEY_ID=
BODS_EXPORT_AWS_SECRET_ACCESS_KEY=
ATHENA_DATABASE=
SQS_QUEUE_URL=
```

Note that this Mongo address must have write access, and the database
tables will be dropped during the tests. For this reason, tests must only be run with
the ENV variable RACK_ENV=test

```
RACK_ENV=test bundle exec rspec
```

This will run any unit and integration tests, which run completely locally and do not
use any AWS resources.

[ End-to-end tests, which spin up a stack and test the whole flow, are in progress. ]
