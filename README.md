### Firehose to Redshift pipeline with Terraform

Code accompanying explanatory [blog post](todo).

### To run this:

First install terraform if you do not have it already.
Then run:
```
terraform init
terraform apply
yarn install
yarn build
yarn server
```

POST some data to `localhost:3000/data` in format `{ "name": "test_value", "value": 1.0 }`

### Destroying created resources
```
terraform destroy
```

This will fail to remove the S3 bucket if there were data created outside of the Terraform configs, so those will have to be deleted manually.

