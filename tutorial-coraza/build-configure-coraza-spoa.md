# Coraza SPOA on Debian 11 and 12

## Prerequisites
Add user `spoa`
```bash
adduser spoa
touch /var/log/coraza.log
chown spoa:spoa /var/log/coraza.log
chmod 660 /var/log/coraza.log
mkdir /etc/coraza-spoa/
chown spoa:spoa /etc/coraza-spoa
```

### Debian 11 : Add backports
Add into `/etc/apt/sources.list`:
```
deb http://deb.debian.org/debian bookworm-backports main
```

Then in bash as `root`:
```bash
apt update
```
### Install build-essential + golang
In bash as `root`:
```bash
apt install build-essential golang git
go version
```
Must return >=`1.18`


## Building SPOA
As `spoa` user:
```bash
git clone https://github.com/corazawaf/coraza-spoa
cd coraza-spoa
make
```
Then as `root`:
```bash
cp /home/spoa/coraza-spoa/coraza-spoa_amd64 /usr/local/bin/coraza-spoa
chmod 555 /usr/local/bin/coraza-spoa
```

## Configuring SPOA

In `/etc/coraza-spoa/config.yaml`

```yaml
bind: 0.0.0.0:9000

default_application: haproxy_spoa

applications:
  haproxy_spoa:
    directives: |
      Include /etc/coraza-spoa/coraza.conf
      Include /etc/coraza-spoa/crs-setup.conf
      Include /etc/coraza-spoa/coreruleset/rules/*.conf

    no_response_check: true

    # The transaction cache lifetime in milliseconds (60000ms = 60s)
    transaction_ttl_ms: 60000
    # The maximum number of transactions which can be cached
    transaction_active_limit: 100000

    # The log level configuration, one of: debug/info/warn/error/panic/fatal
    log_level: info
    log_file: /var/log/coraza.log
```

In `/etc/coraza-spoa/coraza.conf` :
```yaml
SecRuleEngine On
SecRequestBodyAccess On
SecRule REQUEST_HEADERS:Content-Type "^(?:application(?:/soap\+|/)|text/)xml" \
     "id:'200000',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML"

SecRule REQUEST_HEADERS:Content-Type "^application/json" \
     "id:'200001',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=JSON"

SecRequestBodyLimit 131072000
SecRequestBodyInMemoryLimit 1310720
SecRequestBodyNoFilesLimit 1310720
SecRequestBodyLimitAction Reject

SecRule REQBODY_ERROR "!@eq 0" \
"id:'200002', phase:2,t:none,log,deny,status:400,msg:'Failed to parse request body.',logdata:'%{reqbody_error_msg}',severity:2"

SecRule MULTIPART_STRICT_ERROR "!@eq 0" \
"id:'200003',phase:2,t:none,log,deny,status:400, \
msg:'Multipart request body failed strict validation: \
PE %{REQBODY_PROCESSOR_ERROR}, \
BQ %{MULTIPART_BOUNDARY_QUOTED}, \
BW %{MULTIPART_BOUNDARY_WHITESPACE}, \
DB %{MULTIPART_DATA_BEFORE}, \
DA %{MULTIPART_DATA_AFTER}, \
HF %{MULTIPART_HEADER_FOLDING}, \
LF %{MULTIPART_LF_LINE}, \
SM %{MULTIPART_MISSING_SEMICOLON}, \
IQ %{MULTIPART_INVALID_QUOTING}, \
IP %{MULTIPART_INVALID_PART}, \
IH %{MULTIPART_INVALID_HEADER_FOLDING}, \
FL %{MULTIPART_FILE_LIMIT_EXCEEDED}'"

SecRule MULTIPART_UNMATCHED_BOUNDARY "@eq 1" \
    "id:'200004',phase:2,t:none,log,deny,msg:'Multipart parser detected a possible unmatched boundary.'"

SecRule TX:/^COR_/ "!@streq 0" \
        "id:'200005',phase:2,t:none,deny,msg:'Coraza internal error flagged: %{MATCHED_VAR_NAME}'"

SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecResponseBodyLimitAction ProcessPartial
SecDataDir /tmp/

SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:(5|4)(0|1)[0-9])$"
SecAuditLogParts ABIJDEFHZ
SecAuditLogType Serial
SecArgumentSeparator &
SecCookieFormat 0
```


## Installing Core Rule Set
As root:
```bash
cd /etc/coraza-spoa/
git clone https://github.com/coreruleset/coreruleset/
cd coreruleset
git checkout v4.0/main
cp crs-setup.conf.example ../crs-setup.conf
```

Edit `crs-setup.conf`, and add
```
SecAction \
 "id:900200,\
  phase:1,\
  nolog,\
  pass,\
  t:none,\
  setvar:'tx.allowed_methods=GET HEAD POST OPTIONS PUT PATCH DELETE'"
```

## Systemd service
Edit `/etc/systemd/system/coraza-spoa.service`
```systemd
[Unit]
Description=Coraza WAF SPOA Daemon
Documentation=https://www.coraza.io

[Service]
ExecStart=/usr/local/bin/coraza-spoa -config=/etc/coraza-spoa/config.yaml
WorkingDirectory=/home/spoa/
Restart=always
Type=exec
User=spoa
Group=spoa

[Install]
WantedBy=multi-user.target
```

Then, as `root`:
```bash
systemctl daemon-reload
systemctl enable --now coraza-spoa
```

## Configuring HAProxy on the revprox

Create the file `/etc/haproxy/spoe-coraza.conf`

```yaml
[coraza]
spoe-agent coraza-agent
    messages    coraza-req
    option      var-prefix      coraza
    option      set-on-error    error
    timeout     hello           2s
    timeout     idle            2m
    timeout     processing      500ms
    use-backend coraza-spoa
    log         global

spoe-message coraza-req
    args app=str(haproxy_spoa) id=unique-id src-ip=src src-port=src_port dst-ip=dst dst-port=dst_port method=method path=path query=query version=req.ver headers=req.hdrs body=req.body
    event on-frontend-http-request

spoe-message coraza-res
    args app=str(haproxy_spoa) id=unique-id version=res.ver status=status headers=res.hdrs body=res.body
    event on-http-response
```

And in the main haproxy config file `/etc/haproxy/haproxy.cfg`:
```yaml
[...]
frontend web-http
		[...]
  	filter spoe engine coraza config /etc/haproxy/spoe-coraza.conf
		http-request deny deny_status 403 hdr waf-block "request"  if { var(txn.coraza.action) -m str deny }
    http-request deny deny_status 504 if { var(txn.coraza.error) -m int gt 0 }
    http-response deny deny_status 504 if { var(txn.coraza.error) -m int gt 0 }

[...]
backend coraza-spoa
    mode tcp
    server s1 CORAZAIP:9000
    
[...]
		
```

Then restart HAProxy
```bash
systemctl restart haproxy
```

## Behaviour

OK if no attack, `403` code if attack...
Auditlog is at `/var/log/coraza.log`.



