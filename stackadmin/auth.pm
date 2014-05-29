package stackadmin::auth;
use base qw/stackadmin::webhandler/;

use stackadmin::authlib;
use stackadmin::webhandler;
use HTTP::Status qw/:constants :is status_message/;

sub init
{
    @{$_[0]}{qw/foouid fooiv/} = (42, '43760d71bfbcbe90830033d0a0ea5d0e');
}

sub rh_zauth :PATH('POST' => '^/?$')
{
    my ($self) = @_;
    return &r_badrequest unless $ENV{CONTENT_LENGTH} < 512;
    #my $h = &parse0;
    my $h = $self->parse0;
    return &r_badrequest unless defined $h;
    return &r_badrequest unless defined($h->{U}) and defined($h->{P});
    my ($iv, $uid) = $self->noauth($h->{U}, $h->{P});
    return &r_badrequest(403, 'not authorized') unless defined($iv) and defined($uid);
    my $authkey = gen_authkey($iv, $uid, packip());
    return &r_badrequest(418, "i'm probably a teapot because I failed to generate an auth key for you")
        unless defined $authkey;
    sendheaders(HTTP_OK, undef, 'X-Auth-Key' => $authkey);
        #'Set-Cookie' => "xauth=$authkey;Path=/dns/;Domain=.localhost;MaxAge=86000");
}

sub noauth
{
    return @{$_[0]}{qw/fooiv foouid/};
}

1;
