### OpenLiteSpeed as a Reverse Proxy
Environment
```
Port 80  >>> OpenLiteSpeed proxy >>> port 81  Apache
Port 443 >>> OpenLiteSpeed proxy >>> port 444 Apache
```
The script will auto install OpenLiteSpeed, Apache, LSPHP, PHP. Config OLS as a reverse proxy via rewrite rules. 


## How to install
Clone the repository
```
git clone https://github.com/Code-Egg/ols-proxy.git
```

Update `/ols-proxy/backend-cnf` for backend server IP/Port if needed. If URL is not '127.0.0.1', then the setup script will treat the backend server as remote, and skip apache setup. 

```
BACKEND_HTTP_PORT='81'
BACKEND_HTTPS_PORT='444'
BACKEND_IP='127.0.0.1'
BACKEND_DOMAIN='www.example.com'
```

Run the setup script
```
bash /ols-proxy/setup.sh
```

## Optional Settings
Make sure your OpenLiteSpeed version start from v1.7.6+

Enable OWASP ModSecurity rule set on OLS
```
bash owaspctl.sh --enable
```
Disable OWASP ModSecurity rule set on OLS
```
bash owaspctl.sh --disable
```