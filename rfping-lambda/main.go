package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/dynamodb/dynamodbattribute"
	"github.com/google/uuid"
)

var region = os.Getenv("region")

var pathRegexp = regexp.MustCompile(`[0-9a-zA-Z]+`)
var codeRegexp = regexp.MustCompile(`[0-9]{3}`)
var locationRegexp = regexp.MustCompile(`[^ \t\r\n\v\f]`)
var errorLogger = log.New(os.Stderr, "ERROR ", log.Llongfile)
var db = dynamodb.New(session.New(), aws.NewConfig().WithRegion(region))

func listItems() (string, error) {
	var clientArray []Client

	input := &dynamodb.ScanInput{
		TableName: aws.String("Clients"),
	}

	result, err := db.Scan(input)
	if err != nil {
		return "", err
	}

	for _, i := range result.Items {
		client := Client{}
		err = dynamodbattribute.UnmarshalMap(i, &client)
		clientArray = append(clientArray, client)
	}

	clientArrayString, err := json.Marshal(clientArray)
	clarr := string(clientArrayString)

	return clarr, err
}

func putItem(cl Client) error {
	value, err := dynamodbattribute.MarshalMap(cl)

	input := &dynamodb.PutItemInput{
		TableName: aws.String("Clients"),
		Item:      value,
	}

	_, err = db.PutItem(input)

	return err
}

// Client structure for dynamodb
type Client struct {
	UUID string `json:"Uuid"`
	Path string `json:"Path"`
	IP   string `json:"IP"`
	Time string `json:"Time"`
}

func router(req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	switch req.HTTPMethod {
	case "OPTIONS":
		return list(req)
	default:
		return record(req)
	}
}

func list(req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	result, err := listItems()
	if err != nil {
		return serverError(err)
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Body:       string(result),
	}, nil
}

func record(req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var header map[string]string
	path := req.Path
	if !pathRegexp.MatchString(path) {
		return clientError(http.StatusBadRequest)
	}

	respCode := req.QueryStringParameters["code"]
	if !codeRegexp.MatchString(respCode) {
		respCode = "200"
	}

	location := req.QueryStringParameters["location"]
	if !locationRegexp.MatchString(location) {
		location = "/none"
	}

	if location != "/none" && len(location) != 0 {
		header = map[string]string{
			"Location":          location,
			"X-RFPing-Received": "REDIR",
		}
	} else {
		header = map[string]string{
			"X-RFPing-Received": "OK",
		}
	}

	statCode, err := strconv.Atoi(respCode)
	if err != nil {
		return serverError(err)
	}

	cl := Client{
		UUID: uuid.New().String(),
		Path: path,
		IP:   req.RequestContext.Identity.SourceIP,
		Time: time.Now().String(),
	}

	cls, err := json.Marshal(cl)
	if err != nil {
		return serverError(err)
	}

	err = putItem(cl)
	if err != nil {
		return serverError(err)
	}

	return events.APIGatewayProxyResponse{
		StatusCode: statCode,
		Headers:    header,
		Body:       string(cls),
	}, nil
}

func serverError(err error) (events.APIGatewayProxyResponse, error) {
	errorLogger.Println(err.Error())

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusInternalServerError,
		Body:       http.StatusText(http.StatusInternalServerError),
	}, nil
}

func clientError(status int) (events.APIGatewayProxyResponse, error) {
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Body:       http.StatusText(status),
	}, nil
}

func main() {
	lambda.Start(router)
}
