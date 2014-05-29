nginx-fastcgid.pl parses a specified nginx backend definition and spawns fastcgi servers through fastcgi.pl script.

#nginx backend definition
nginx-fastcgid.pl looks for backends who's name matches the pattern:
```
fastcgi-($ARGV[0]) { ... }
```
where $ARGV[0] is the argument specified when running nginx-fastcgid.pl

### running nginx-fastcgid
you would normally run nginx-fastcgid.pl like this:
```bash
FCGIUID=99 \
FCGIAPP=stackadmin.web \
FASTCGI_CONF=/path/to/upstreams-def.conf \
FASTCGI_PROGRAM=./fastcgi.pl \
./nginx-fastcgid.pl <backend-name>

```

FCGIUID=0 FCGIAPP=stackadmin::web FASTCGI_CONF=./nginx/00-upstreams.conf FASTCGI_PROGRAM=./fastcgi.pl ./nginx-fastcgid.pl flup

