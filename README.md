# rfping
AWS Lambda for SSRF testing (Similar to Burp Collaborator)

## Example usage

### Record HTTP request URL
Details will be permanently stored in DynamoDB.
```
curl "https://yfo4rqrd55.execute-api.eu-west-2.amazonaws.com/rfping/SoMeTeStStRiNG"
```

### Trigger a HTTP redirect
Details will be permanently stored in DynamoDB.
```
curl "https://yfo4rqrd55.execute-api.eu-west-2.amazonaws.com/rfping/SoMeTeStStRiNG?code=302&location=http://evil.com/xxx"
```

### List recorded HTTP requests
Access to list of recorded requests is limited to public IP from terraform launch
```
curl "https://yfo4rqrd55.execute-api.eu-west-2.amazonaws.com/rfping/SoMeTeStStRiNG" -X OPTIONS
```
