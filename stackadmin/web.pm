
package stackadmin::web;
use Data::Dumper;

use stackadmin::auth;
use stackadmin::dns;
use stackadmin::code;
my %mods = (
    'auth' => stackadmin::auth->new(),
    'dns' => stackadmin::dns->new(),
    'code' => stackadmin::code->new(),
);

my $defaultmod = stackadmin::nohandler->new();

sub new
{
    return bless {} , __PACKAGE__;
}

sub lookup
{
    my($empty, $modpath, $app) = split /\//, $ENV{DOCUMENT_URI}, 3;
    $ENV{PATH_INFO} = $app;
    #warn "web.pm: return $mods{$modpath} for url $modpath";
    return $mods{$modpath} // $defaultmod;
}
1;

package stackadmin::nohandler;
use Data::Dumper;
sub new
{
    return bless {}, __PACKAGE__;
}
sub run
{
    #warn Dumper(\%ENV);
    print <<EOH
Server: quuxbaz/7.1-fastcgi\r
Status: 404 deadend\r
\r
EOH
;
}

sub reset {}
sub terminate {}

1;
