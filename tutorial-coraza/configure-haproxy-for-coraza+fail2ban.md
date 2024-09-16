# Configure existing HAProxy to use Coraza and fail2ban
All commands as `root` unless specified.

## HAProxy

### Create /etc/haproxy/spoe-coraza.conf

```bash
[coraza]
spoe-agent coraza-agent
    messages    coraza-req
    option      var-prefix      coraza
    option      set-on-error    error
    timeout     hello           5s
    timeout     idle            2m
    timeout     processing      1000ms
    use-backend coraza-spoa
    log         global

spoe-message coraza-req
    args app=str(haproxy_spoa) id=unique-id src-ip=src src-port=src_port dst-ip=dst dst-port=dst_port method=method path=path query=query version=req.ver headers=req.hdrs body=req.body
    event on-frontend-http-request

spoe-message coraza-res
    args app=str(haproxy_spoa) id=unique-id version=res.ver status=status headers=res.hdrs body=res.body
    event on-http-response
```

### Modify existing /etc/haproxy/haproxy.cfg
```bash

<In frontend:>
    log-format "%ci:%cp\ [%t]\ %ft\ %b/%s\ %Th/%Ti/%TR/%Tq/%Tw/%Tc/%Tr/%Tt\ %ST\ %B\ %CC\ %CS\ %tsc\ %ac/%fc/%bc/%sc/%rc\ %sq/%bq\ %hr\ %hs\ %{+Q}r\ %ID\ wafaction:%[var(txn.coraza.action)]\ wafruleid:%[var(txn.coraza.ruleid)]\ wafstatus:%[var(txn.coraza.status)]\ wafdata:%[var(txn.coraza.data)]"

    unique-id-format %[uuid()]
    unique-id-header X-Unique-ID
    filter spoe engine coraza config /etc/haproxy/spoe-coraza.conf
    
    # Currently haproxy cannot use variables to set the code or deny_status, so this needs to be manually configured here
    http-request redirect code 302 location %[var(txn.coraza.data)] if { var(txn.coraza.action) -m str redirect }
    http-response redirect code 302 location %[var(txn.coraza.data)] if { var(txn.coraza.action) -m str redirect }
    http-request deny deny_status 403 hdr waf-block "request"  if { var(txn.coraza.action) -m str deny }
    http-response deny deny_status 403 hdr waf-block "response" if { var(txn.coraza.action) -m str deny }
    http-request silent-drop if { var(txn.coraza.action) -m str drop }
    http-response silent-drop if { var(txn.coraza.action) -m str drop }
    # Deny in case of an error, when processing with the Coraza SPOA
    http-request deny deny_status 504 if { var(txn.coraza.error) -m int gt 0 }
    http-response deny deny_status 504 if { var(txn.coraza.error) -m int gt 0 }


backend coraza-spoa
    mode tcp
    balance roundrobin
    timeout connect 5s
    timeout server 3m
    server s1 <IP>:9000
```

Remove references to `mod_security2`.

### Restart HAProxy
```bash
systemctl restart haproxy
```

## fail2ban

Install `fail2ban`

```bash
apt update
apt install fail2ban
```

Create `/etc/fail2ban/filter.d/haproxy-coraza.conf`
```
[INCLUDES]

before = common.conf


[Definition]

_daemon = haproxy

failregex = ^.* (\S+) (\S+)\[(\d+)\]: <HOST>:(\d+) \[(.*)\] (\S*) (\S*) \S+ (\d+) .* \"(.*)\" (\S*) wafaction:deny wafruleid:(\d+)

ignoreregex =

```

Create `/etc/fail2ban/filter.d/haproxy-dos.conf`
```
[INCLUDES]

before = common.conf


[Definition]

_daemon = haproxy

failregex = ^.* (\S+) (\S+)\[(\d+)\]: <HOST>:(\d+) \[(.*)\] (\S*) (\S*) \S+ (\d+) .* \"(.*)\" (\S*)

ignoreregex =

```

Create `/etc/fail2ban/jail.d/haproxy-coraza.conf`
```
[haproxy-coraza-immediate]
enabled = true
filter  = haproxy-coraza
logpath = /var/log/haproxy.log
bantime = X
findtime = Y
maxRetry = Z

[haproxy-coraza-long]
enabled = true
filter  = haproxy-coraza
logpath = /var/log/haproxy.log
bantime = X
findtime = Y
maxRetry = Z

[haproxy-dos-immediate]
enabled = true
filter  = haproxy-dos
logpath = /var/log/haproxy.log
bantime = X
findtime = Y
maxRetry = Z

[haproxy-dos-hour]
enabled = true
filter  = haproxy-dos
logpath = /var/log/haproxy.log
bantime = X
findtime = Y
maxRetry = Z
```

At last, create `/etc/fail2ban/jail.local`

```
[INCLUDES]
before = paths-debian.conf

[DEFAULT]
ignoreself = true
ignoreip = 127.0.0.1/8 ::1
ignorecommand =

bantime  = 10m
findtime  = 10m
maxretry = 5
maxmatches = %(maxretry)s
backend = auto
usedns = warn
logencoding = auto
enabled = false
mode = normal
filter = %(__name__)s[mode=%(mode)s]

# ACTIONS
destemail = root@localhost
sender = root@<fq-hostname>
mta = sendmail
protocol = tcp
chain = <known/chain>
port = 0:65535
fail2ban_agent = Fail2Ban/%(fail2ban_version)s

banaction = iptables-multiport
banaction_allports = iptables-allports

action_ = %(banaction)s[port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mw = %(action_)s
            %(mta)s-whois[sender="%(sender)s", dest="%(destemail)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mwl = %(action_)s
             %(mta)s-whois-lines[sender="%(sender)s", dest="%(destemail)s", logpath="%(logpath)s", chain="%(chain)s"]

action_xarf = %(action_)s
             xarf-login-attack[service=%(__name__)s, sender="%(sender)s", logpath="%(logpath)s", port="%(port)s"]
action_cf_mwl = cloudflare[cfuser="%(cfemail)s", cftoken="%(cfapikey)s"]
                %(mta)s-whois-lines[sender="%(sender)s", dest="%(destemail)s", logpath="%(logpath)s", chain="%(chain)s"]
action_blocklist_de  = blocklist_de[email="%(sender)s", service="%(__name__)s", apikey="%(blocklist_de_apikey)s", agent="%(fail2ban_agent)s"]
action_badips = badips.py[category="%(__name__)s", banaction="%(banaction)s", agent="%(fail2ban_agent)s"]
action_badips_report = badips[category="%(__name__)s", agent="%(fail2ban_agent)s"]
action_abuseipdb = abuseipdb

action = %(action_)s
```

Then enable and restart `fail2ban`
```
systemctl enable --now fail2ban
```