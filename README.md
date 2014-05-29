nginx-fastcgid.pl parses a specified nginx backend definition and spawns fastcgi servers through fastcgi.pl script.

###nginx backend definition
nginx-fastcgid.pl looks into nginx config specified via env with FASTCGI_CONF for backends who's name matches the pattern:
```
fastcgi-($ARGV[0]) { ... }
```
where $ARGV[0] is the argument specified when running nginx-fastcgid.pl

the upstreams can be either tcp or unix sockets.

### running nginx-fastcgid
you would normally run nginx-fastcgid.pl like this:
```bash
FCGIUID=99 \
FCGIAPP=stackadmin.web \
FASTCGI_CONF=/path/to/upstreams-def.conf \
FASTCGI_PROGRAM=./fastcgi.pl \
./nginx-fastcgid.pl <backend-name>

```
### starting the web app

the included fastcgi.pl script runs the specified web app. an example is included, stackadmin::web, in which you register your app handlers within a %mod hash.
the app handlers must inherit stackadmin::webhandler;
two sample app handlerls are included, auth and code.

