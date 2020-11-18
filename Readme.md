### OpenLiteSpeed as a Reverse Proxy
Port 80  >>> OpenLiteSpeed proxy >>> port 81  Apache
Port 443 >>> OpenLiteSpeed proxy >>> port 444 Apache

The script will auto install OpenLiteSpeed, Apache, LSPHP, PHP. Config OLS as a reverse proxy via rewrite rules. 


## How to Setup
Clone the repository
```
git clone https://github.com/Code-Egg/ols-proxy.git
```
Run the setup script
```
cd; bash setup.sh
```

## Optional Settings
Enable OWASP ModSecurity rule set on OLS
```
bash owaspctl.sh --enable
```
Disable OWASP ModSecurity rule set on OLS
```
bash owaspctl.sh --disable
```