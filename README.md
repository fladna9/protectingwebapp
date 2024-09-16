# Protecting web applications with FOSS

## Contents

### presentation folder

Contains the slides for the talk **Protecting web applications with FOSS**

### tutorial-coraza folder

Contains tutorial and support files (systemd service, configuration files, etc.) for you to be able to have HAProxy + Coraza SPOA + CoreRuleSet 4 + fail2ban


### tutorial-modsec2 folder

Contains a bash script (run at your own risk) to compile and be ready to use mod_security2 SPOA.
More info about configuration in links below.
Be careful, on the `haproxy.cfg` file to add `maxconn #THREADS` that you added in mod_security SPOA command line/systemd service.

## Licenses

### Talk / presentation folder

The talk slides are licensed under CC BY 4.0.
https://creativecommons.org/licenses/by/4.0/deed.en

### Support files and tutorials

Support files and tutorials are licensed under Apache 2.0 license.

```
Copyright 2024 fladna9

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```


## Sources and links

HAProxy: https://www.haproxy.org/

HAProxy on Debian: https://packages.debian.org/bookworm/haproxy or https://haproxy.debian.net/

HAProxy documentation: http://docs.haproxy.org/

Coraza: https://coraza.io/

Coraza documentation: https://coraza.io/docs/tutorials/introduction/

Coraza SPOA GitHub repository: https://github.com/corazawaf/coraza-spoa

mod_security2 GitHub repository: https://github.com/owasp-modsecurity/ModSecurity

mod_security2 SPOA GitHub repository: https://github.com/haproxy/spoa-modsecurity
