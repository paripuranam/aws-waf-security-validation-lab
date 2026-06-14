# AWS WAF Attack & Defense Lab — SQL Injection and DDoS Validation

End-to-end security validation lab deploying an OWASP Vulnerable Web Application behind an ALB with AWS WAF — tests SQL injection and DDoS attacks in a controlled environment, validates WAF blocking with sampled request logs and CloudWatch evidence.

---

## Architecture

```
Internet
    │
    ▼
AWS WAF (Web ACL: test-app-waf)
  ├── Rule 1: AWS-AWSManagedRulesSQLiRuleSet (BLOCK)
  │     └── SQLi_QUERYARGUMENTS, SQLi_BODY, SQLi_COOKIE, SQLi_URIPATH
  └── Rule 2: BlockHighRequestRate (custom — BLOCK)
              └── >1000 requests per IP per 5 minutes
    │
    ▼
Application Load Balancer (test-app-alb)
    │
    ▼
EC2 Instance (Amazon Linux 2023, t2.micro)
    └── OWASP Vulnerable Web Application (Apache httpd)
          ├── SQL Injection endpoint
          ├── XSS endpoint
          ├── Command Execution
          └── File Upload
    │
    ▼
CloudWatch Logs (vulnerable-app-logs)
    └── Log stream: instance/app-logs
```

---

## Setup

### Step 1 — EC2 + Application Deployment

```bash
# Update OS
sudo yum update -y

# Install and enable Apache
sudo yum install httpd -y
sudo systemctl enable httpd && sudo systemctl start httpd

# Clone OWASP Vulnerable Web Application
cd /var/www/html
git clone https://github.com/OWASP/Vulnerable-Web-Application.git

# Move files and set index
cd Vulnerable-Web-Application
mv * /var/www/html
cd ..
mv homepage.html index.html

# Restart Apache
sudo systemctl restart httpd
```

### Step 2 — CloudWatch Agent Setup

```bash
# Install CloudWatch agent
sudo yum install amazon-cloudwatch-agent -y
sudo systemctl enable amazon-cloudwatch-agent && sudo systemctl start amazon-cloudwatch-agent
```

**CloudWatch agent config** (`/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`):

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/httpd/access_log",
            "log_group_name": "vulnerable-app-logs",
            "log_stream_name": "instance/app-logs",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
```

```bash
sudo systemctl restart amazon-cloudwatch-agent
```

---

## WAF Rules

### Rule 1 — AWS Managed SQLi Rule Set

```json
{
  "Name": "AWS-AWSManagedRulesSQLiRuleSet",
  "Priority": 1,
  "OverrideAction": { "None": {} },
  "Statement": {
    "ManagedRuleGroupStatement": {
      "VendorName": "AWS",
      "Name": "AWSManagedRulesSQLiRuleSet"
    }
  },
  "VisibilityConfig": {
    "SampledRequestsEnabled": true,
    "CloudWatchMetricsEnabled": true,
    "MetricName": "AWS-AWSManagedRulesSQLiRuleSet"
  }
}
```

All sub-rules overridden to **BLOCK**: SQLi_QUERYARGUMENTS, SQLi_BODY, SQLi_COOKIE, SQLi_URIPATH, SQLiExtendedPatterns_QUERYARGUMENTS.

### Rule 2 — Custom DDoS Rate Limit

```json
{
  "Name": "BlockHighRequestRate",
  "Priority": 2,
  "Statement": {
    "RateBasedStatement": {
      "Limit": 1000,
      "EvaluationWindowSec": 300,
      "AggregateKeyType": "IP"
    }
  },
  "Action": { "Block": {} },
  "VisibilityConfig": {
    "SampledRequestsEnabled": true,
    "CloudWatchMetricsEnabled": true,
    "MetricName": "BlockHighRequestRate"
  }
}
```

Blocks any IP sending more than 1000 requests per 5-minute window.

---

## Attack Validation

### SQL Injection Test

**Attack URL:**
```
http://ALB-DNS/login?id=%27%20OR%201=1%20/*
```

**WAF Sampled Request Evidence:**
```json
{
  "Source IP": "125.99.238.18",
  "Country": "IN",
  "URI": "/login?id=%27%20OR%201=1%20/*",
  "Rule": "AWS#AWSManagedRulesSQLiRuleSet#SQLi_QUERYARGUMENTS",
  "Action": "BLOCK",
  "Time": "Fri Jan 24 2025 12:47:22 GMT+0530"
}
```

**Result:** HTTP 403 Forbidden — WAF blocked before request reached ALB.

---

### DDoS Simulation with k6

**k6 script** (`load-testing/k6-script.js`):

```javascript
import http from 'k6/http';

export const options = {
  scenarios: {
    excessive_requests: {
      executor: 'constant-arrival-rate',
      rate: 1500,
      duration: '1m',
      preAllocatedVUs: 50,
      maxVUs: 100,
    },
  },
};

export default function () {
  const url = 'http://YOUR-ALB-DNS/';
  http.get(url);
}
```

```bash
# Install k6
sudo apt install k6

# Run DDoS simulation
k6 run script.js
```

**k6 Results:**
```
http_reqs:     21,909  (363.71/s)
http_blocked:  avg=1.08ms
VUs:           70 (min=57, max=100)
Duration:      1m0s
```

**WAF DDoS Block Evidence:**
```json
{
  "Source IP": "125.99.238.18",
  "Rule": "BlockHighRequestRate",
  "Action": "BLOCK",
  "Time": "Fri Jan 24 2025 12:57:41 GMT+0530",
  "User-Agent": "k6/0.56.0 (https://k6.io/)"
}
```

**Result:** All requests above threshold blocked — application remained available.

---

## Skills Demonstrated

- AWS WAF — managed rule groups (SQLi), custom rate-based rules, sampled request logging
- Attack simulation — SQL injection (URL-encoded payloads), DDoS (k6 at 1500 req/min, 100 VUs)
- CloudWatch — agent configuration, log group and stream setup, access log collection
- ALB — target group, health checks, listener configuration
- OWASP Top 10 — A03:2021 Injection (SQLi), denial of service validation
- Security validation methodology — before/after evidence, sampled request proof

---
