import express from "express";
import bodyParser from "body-parser";
import AWS, { SharedIniFileCredentials, Firehose } from "aws-sdk";

// Overide default config to use desired profile. There are multiple ways how to do that.
// Check https://docs.aws.amazon.com/sdk-for-javascript/v2/developer-guide/loading-node-credentials-shared.html
AWS.config = new AWS.Config({
  credentials: new SharedIniFileCredentials({
    profile: "test-profile"
  }),
  // Event with correct config file with region for profile, this still seems to be needed explicitly.
  region: "us-east-1"
});
const firehoseClient = new Firehose();

const app = express();

app.use(bodyParser.json());

app.post("/data", async (req, res, next) => {
  try {
    // For production, putRecordBatch should be more efficient.
    await firehoseClient
      .putRecord({
        Record: {
          Data: JSON.stringify({
            timestamp: new Date(),
            ...req.body
          })
        },
        DeliveryStreamName: "test_pipeline_firehose"
      })
      .promise();

    res.sendStatus(200);
  } catch (err) {
    next(err);
  }
});

let port = process.env.PORT || 3000;
app.listen(port, function() {
  console.log("Server listening on port " + port);
});
