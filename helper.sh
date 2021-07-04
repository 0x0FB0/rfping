env GOOS=linux GOARCH=amd64 go build -o /tmp/main /rfping-lambda/main.go
zip -j /tmp/main.zip /tmp/main
terraform init
terraform plan
terraform apply -auto-approve 
