"""KilnWatch API placeholder.

Replace this handler with application logic. The Terraform starter intentionally
does not embed DB passwords or a PostgreSQL driver. Use AWS Secrets Manager and
package a compatible driver/layer before querying RDS.
"""
import json

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }

def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "/health")

    if method == "GET" and path == "/health":
        return response(200, {"status": "ok", "service": "kilnwatch-api",
                              "note": "Infrastructure placeholder; connect database logic next."})

    # TODO: Validate the Cognito claims, query PostgreSQL/PostGIS, and return
    # records from the database. Do not return fake compliance conclusions.
    if method == "GET" and path in ("/kilns", "/public/kilns"):
        return response(200, {"items": [], "nextToken": None,
                              "note": "Connect this route to RDS/PostGIS."})

    if method == "GET" and path.startswith("/kilns/"):
        return response(404, {"message": "Kiln not found; connect this route to RDS/PostGIS."})

    if method == "POST" and path == "/jobs":
        return response(501, {"message": "TODO: validate job input and call Step Functions StartExecution."})

    return response(404, {"message": "Route not implemented."})
