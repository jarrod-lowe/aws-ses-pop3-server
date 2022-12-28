/*
   Copyright 2022 Markus Hinz

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

package provider

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/lambda"
)

type ProviderCreator func(user, password string) (Provider, error)

type Provider interface {
	ListEmails(notNumbers []int) (emails map[int]*Email, err error)
	GetEmail(number int, notNumbers []int) (email *Email, err error)
	GetEmailPayload(number int, notNumbers []int) (payload EmailPayload, err error)
	DeleteEmail(number int) (err error)
}

type S3Bucket struct {
	AWSAccessKeyID     string `json:"awsAccessKeyID,omitempty"`
	AWSSecretAccessKey string `json:"awsSecretAccessKey,omitempty"`
	AWSSessionToken    string `json:"awsSessionToken,omitempty"`
	Region             string `json:"region,omitempty"`
	Bucket             string `json:"bucket,omitempty"`
	Prefix             string `json:"prefix,omitempty"`
}

type JWTClaims struct {
	jwt.StandardClaims
	Provider string `json:"provider,omitempty"`
	S3Bucket
}

type StaticCredentials struct {
	User     string
	Password string
	S3Bucket *S3Bucket
}

type LambdaPayload struct {
	User     string
	Password string
}

type LambdaResponse struct {
	StatusCode int
	S3Bucket
}

func NewStaticCredentialsProviderCreator(staticCreds StaticCredentials) ProviderCreator {
	return func(user, password string) (Provider, error) {
		if user == staticCreds.User && password == staticCreds.Password {
			if staticCreds.S3Bucket != nil {
				return newS3Provider(*staticCreds.S3Bucket)
			}
			return newNoneProvider()
		}
		return nil, errors.New("credentials do not match user/password")
	}
}

func NewJWTProviderCreator(jwtSecret string) ProviderCreator {
	return func(_, password string) (Provider, error) {
		claims := JWTClaims{}
		if _, err := jwt.ParseWithClaims(password, &claims, func(token *jwt.Token) (interface{}, error) {
			return []byte(jwtSecret), nil
		}); err != nil {
			return nil, err
		}
		switch true {
		case strings.EqualFold(claims.Provider, "none"):
			return newNoneProvider()
		case strings.EqualFold(claims.Provider, "demo"):
			return newNoneProvider(DemoEmail)
		case claims.Provider == "" || strings.EqualFold(claims.Provider, "s3"):
			return newS3Provider(S3Bucket{
				AWSAccessKeyID:     claims.AWSAccessKeyID,
				AWSSecretAccessKey: claims.AWSSecretAccessKey,
				AWSSessionToken:    claims.AWSSessionToken,
				Region:             claims.Region,
				Bucket:             claims.Bucket,
				Prefix:             claims.Prefix,
			})
		}
		return nil, errors.New("provider must be either be '', 'none', 'demo' or 's3'")
	}
}

func NewHTTPBasicAuthProviderCreator(timeout time.Duration, url string) ProviderCreator {
	client := &http.Client{
		Timeout: timeout,
	}
	return func(user, password string) (Provider, error) {
		req, err := http.NewRequest("GET", url, nil)
		if err != nil {
			return nil, err
		}
		req.SetBasicAuth(user, password)
		res, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		defer res.Body.Close()
		if res.StatusCode != 200 {
			return nil, fmt.Errorf("received status code %v", res.StatusCode)
		}
		var bucket S3Bucket
		if err := json.NewDecoder(res.Body).Decode(&bucket); err != nil {
			return nil, err
		}
		return newS3Provider(bucket)
	}
}

func NewLambdaProviderCreator(timeout time.Duration, function string) ProviderCreator {
	sess, err := session.NewSession() // TODO: Args for key?
	if err != nil {
		panic(err)
	}
	return func(user, password string) (Provider, error) {
		client := lambda.New(sess)
		payload := LambdaPayload{
			User:     user,
			Password: password,
		}

		payloadJson, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}

		res, err := client.Invoke(&lambda.InvokeInput{
			FunctionName:   aws.String(function),
			InvocationType: aws.String("RequestResponse"),
			Payload:        payload,
		})
		if err != nil {
			return nil, err
		}

		var lambdaResponse LambdaResponse
		if err := json.NewDecoder(res.Payload).Decode(&lambdaResponse); err != nil {
			return nil, err
		}

		if lambdaResponse.StatusCode != 200 {
			return nil, fmt.Errorf("received status code %v", lambdaResponse.StatusCode)
		}

		return new S3Provider(lambdaResponse)
	}
}