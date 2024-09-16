#!/bin/bash
# apt update
# apt install git liblua5.3-0 liblua5.3-dev
WORKINGDIR="/root/"

function main() {
    cleanUpFull
    compileModSecurity
    compileSPOAModsecurity
    installCoreRuleSet
    installSPOAModsecurity
    sudo systemctl restart spoa-modsecurity
    #cleanUp
}

function compileModSecurity() {
    cd "$WORKINGDIR"
    git clone https://github.com/SpiderLabs/ModSecurity
    cd ModSecurity
    git checkout v2/master
    git pull
    ./autogen.sh
    ./configure --disable-apache2-module --enable-standalone-module --enable-pcre-study --with-lua=/usr/include/lua5.4 --enable-pcre-jit
    make && sudo make -C standalone install
}

function compileSPOAModsecurity() {
    cd "$WORKINGDIR"
    git clone https://github.com/haproxy/spoa-modsecurity
    cd spoa-modsecurity
    sudo rm /usr/lib/liblua.so
    sudo ln -s /usr/lib/x86_64-linux-gnu/liblua5.3.so /usr/lib/liblua.so
    mkdir -p ./INSTALL/include
    mkdir ./INSTALL/lib/
    cp /usr/local/modsecurity/lib/standalone.a ./INSTALL/lib/
    cp "$WORKINGDIR"/ModSecurity/standalone/*.h ./INSTALL/include
    cp "$WORKINGDIR"/ModSecurity/apache2/*.h ./INSTALL/include
    LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$WORKINGDIR/spoa-modsecurity/INSTALL/lib:/usr/lib/ MODSEC_INC=$WORKINGDIR/spoa-modsecurity/INSTALL/include MODSEC_LIB=$WORKINGDIR/spoa-modsecurity/INSTALL/lib APACHE2_INC=/usr/include/apache2/ APR_INC=/usr/include/apr-1.0/ LIBS="$LIBS -llua" make
    cp modsecurity "$WORKINGDIR/spoa"
}

function installCoreRuleSet() {
    cd "$WORKINGDIR"
    #wget "https://github.com/coreruleset/coreruleset/archive/refs/tags/v3.3.5.zip" -O "crs-3.3.5.zip"
    #unzip "crs-3.3.5.zip"
    git clone "https://github.com/coreruleset/coreruleset/"
    cd coreruleset
    git checkout "$(git tag -l | grep -P 'v3.*[^rc]\d$' | tail -n-1)"
    git pull

    if [[ -d /opt/spoa-modsec/coreruleset ]]; then 
        sudo rm -rf /opt/spoa-modsec/coreruleset
    fi

    cd "$WORKINGDIR"
    sudo mv coreruleset /opt/spoa-modsec/
    #sudo cp /opt/spoa-modsec/template-files/spoa.conf /opt/spoa-modsec/coreruleset/
    sudo cat > /opt/spoa-modsec/coreruleset/spoa.conf << EOF
SecRuleEngine On
SecRequestBodyAccess On
SecTmpDir /tmp/
SecDataDir /tmp/
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"
SecAuditLogParts ABIJDEFHZ
SecAuditLogType Serial
SecAuditLog /var/log/modsec_audit.log
SecDebugLog /var/log/modsec_debug.log
SecArgumentSeparator &
SecCookieFormat 0
SecStatusEngine Off
include ./crs-setup.conf
include ./rules/*.conf
# Règles à ignorer
# Pas de methodes chelous
SecRuleRemoveById SecRuleRemoveByID 911100
# Pas de verification de content-type
SecRuleRemoveById SecRuleRemoveByID 920420
SecRuleRemoveById SecRuleRemoveByID 941100
SecRuleRemoveById SecRuleRemoveByID 921110
EOF

    sudo cp /opt/spoa-modsec/coreruleset/crs-setup.conf.example /opt/spoa-modsec/coreruleset/crs-setup.conf
    sudo cat >> /opt/spoa-modsec/coreruleset/spoa.conf << EOF

SecAction \
 "id:900200,\
  phase:1,\
  nolog,\
  pass,\
  t:none,\
  setvar:'tx.allowed_methods=GET HEAD POST OPTIONS PROPFIND REPORT PUT'"
EOF
    #sudo cat /opt/spoa-modsec/template-files/crs-setup.conf >> /opt/spoa-modsec/coreruleset/crs-setup.conf
    sudo chown -R spoa:spoa /opt/spoa-modsec
}

function installSPOAModsecurity() {
    sudo rm /opt/spoa-modsec/bin/spoa
    sudo cp "$WORKINGDIR"/spoa /opt/spoa-modsec/bin/spoa
}

function cleanUp() {
    cd "$WORKINGDIR"
    if [[ -d "$WORKINGDIR/ModSecurity" ]]; then
        rm -rf "$WORKINGDIR/ModSecurity"
    fi

    if [[ -d "$WORKINGDIR/spoa-modsecurity" ]]; then
        rm -rf "$WORKINGDIR/spoa-modsecurity"
    fi
    if [[ -d "$WORKINGDIR/coreruleset" ]]; then
        rm -rf "$WORKINGDIR/coreruleset"
    fi

}

function cleanUpFull() {
    cleanUp

    if [[ -f "$WORKINGDIR/spoa" ]]; then
        rm spoa
    fi
}

main $@

