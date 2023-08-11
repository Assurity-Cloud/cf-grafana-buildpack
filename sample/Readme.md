#### Overview

Just a simple CF application to test Grafana

Change the parameters in the manifest and push to CF with `cf push`.

#### Steps

Create Service Instance(s):
```shell
cf create-service csb-aws-influxdb default manuel-one -c '{ "name": "manuel-one", "databases": [ "ess", "foo", "bar" ], "retention_policies": { "cloudflare": [ { "name": "cloudflare-90d", "duration": "90d" } ] }, "influxdb_image_version": "v1.8.10_ap0.0.8", "cpu": 2048, "memory": 4096 }'
cf create-service csb-aws-influxdb default manuel-two -c '{ "name": "manuel-two", "databases": [ "ess", "foo", "bar" ], "retention_policies": { "cloudflare": [ { "name": "cloudflare-90d", "duration": "90d" } ] }, "influxdb_image_version": "v1.8.10_ap0.0.8", "cpu": 2048, "memory": 4096 }'
```

Change parameters in the `manifest` if/as needed and push to CF with `cf push --no-start`.

```shell
cf bind-service mygrafana manuel-one --binding-name "manuel-one" -c '{ "database_privileges": [ { "database": "cust_metrics", "privilege": "ALL" }, { "database": "cloudflare", "privilege": "ALL" } ] }'
cf bind-service mygrafana manuel-two --binding-name "manuel-two" -c '{ "database_privileges": [ { "database": "ess", "privilege": "ALL" }, { "database": "foo", "privilege": "ALL" }, { "database": "bar", "privilege": "ALL" } ] }'
```

Start `mygrafana` app by running `cf start mygrafana`