package stackadmin::webhandler;
use v5.18;
use strict;
use warnings;
no warnings "experimental::smartmatch";
use stackadmin::authlib;
use Attribute::Handlers;
use DBI;
use HTTP::Status qw/:constants :is status_message/;
use Data::Dumper;
use MIME::Base64;
use JSON::XS;


require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/sendheaders r_badrequest/;

use constant {
    EOR => "\r\n",
    RC_NEXT => 0,
    RC_LAST => 1,
};

sub decorate(&$)
{
    my($coderef, $symbol) = @_;
    {
        no warnings 'redefine';
        *$symbol = $coderef;
    }
}

sub checkauth
{
    my($self) = @_;
    my $authkey = $ENV{HTTP_X_AUTH_KEY};
    #warn "check_auth: X-Auth-Key=$authkey";
    return undef unless (defined($authkey)) and (length($authkey) == 49) and ($authkey=~/\$$/);
    $authkey=~s/\$/\n/g;
    my($data,$uid) = unpack('a32N', decode_base64($authkey));
    return undef unless defined($uid) and $uid > 0;
    my($iv) = $self->db->selectrow_array($self->prepstmt('ivok'), {}, $uid);
    return undef unless defined($iv) and &check_authkey($data, $iv, $uid);
    return $uid;
}


#edit this to register origins
our @allowed_domains = ();

sub REQUIRE_AUTH :ATTR(CODE,BEGIN)
{
    my($pkg, $glob, $code) = @_;
    decorate {
        #warn Dumper(\%ENV);
        #warn "RUNDECORATOR(REQUIRE_AUTH)";
        my $uid = $_[0]->checkauth();
        #my $uid = $_[0]->check_auth;
        return r_needauth() unless $uid;
        $_[0]->uid = $uid;
        return $code->(@_);
    } $glob;
}

sub PATH :ATTR(CODE,BEGIN)
{
    my ($pkg, $glob, $code, $attr, $data) = @_;
    my ($methods, $urls) = map { qr/$_/ } @$data;
    die "bad path pattern specified for $attr"
        unless defined $methods and defined $urls;

    #warn "DECORATOR(PATH): data=@$data";
    decorate {
        return 0 unless ($ENV{REQUEST_METHOD}=~/$methods/) or $ENV{REQUEST_METHOD} eq 'OPTIONS' ;
        my $path_info = $ENV{PATH_INFO} // '';
        #my $m = $1;
        #warn "TRY_MATCH " . *{$glob}{NAME} . ", PATH_INFO=$path_info, regpath=$urls";
        return 0 unless $path_info =~ /$urls/;
        my @matches = map {substr($path_info, $-[$_], $+[$_] - $-[$_])} (1..$#-) ;
        my @pparams = split /&/, $ENV{QUERY_STRING};
        my %args = ();
        foreach my $pparam (@pparams) {
            my ($k,$v) = split /=/, $pparam;
            $args{$k} = $v;
        }
        #warn "URL_MATCH: " . *{$glob}{NAME};
        return $code->(@_, \%args, @matches);
    } $glob;
}


sub terminate
{
    say __PACKAGE__ . ":cleanup for exit";
    $_[0]->{db}->disconnect;
}
sub reset
{
    my ($self) = @_;
    delete $self->{stash};
    delete $self->{uid};
}

sub db { $_[0]->{db} }


sub prepstmt
{
    my $self = shift;
    return $self->{ps}->{$_[0]} if scalar @_ == 1;
    die "badargs" unless scalar(@_) % 2 == 0;
    my %args = @_;
    foreach my $pn (keys %args) {
        die "a query named $pn already exists" if defined $self->{ps}->{$pn};
        $self->{ps}->{$pn} = $self->db->prepare($args{$pn});
    }
}

sub uid :lvalue
{
    my ($self, $uid) = @_;
    if(defined($uid)) {
        $self->{stash}->{uid} = $uid;
        return $uid;
    }
    return $self->{stash}->{uid};
}

sub new
{
    my $self = {
        ps => {},
    };
    bless $self, $_[0];
    $self->init;
    my @handlers = $self->setup_handlers;
    $self->handlers = \@handlers;
    return $self;
}

my $rheaders = <<EOH
Server: quuxbaz/7.1-fastcgi\r
Status: %d %s\r
EOH
;

sub default_handler :REQUIRE_AUTH 
{ 
    #warn Dumper(\%ENV);
    sendheaders(404, undef, 'X-Default-Handler' => 'True');
}

sub sendheaders
{
    my ($code, $clen, %headers) = @_;
    if(defined($clen) and $clen > 0) {
        @headers{qw/Content-Type Content-Length/} = ('application/json', $clen);
    }
    unless(defined($headers{'Access-Control-Allow-Origin'})) {
        my ($origin) = ($ENV{HTTP_ORIGIN}=~/http:\/\/([^\/]+)/);
        if($origin ~~ @allowed_domains) {
            @headers{qw/
                Access-Control-Allow-Origin 
                Access-Control-Allow-Methods 
                Access-Control-Allow-Headers 
                Access-Control-Allow-Credentials
                Access-Control-Expose-Headers/
            } = (
                $ENV{HTTP_ORIGIN} // 'http://dev.stackadmin.com',
                'GET,POST,PUT,DELETE,OPTIONS',
                $ENV{HTTP_ACCESS_CONTROL_REQUEST_HEADERS} // 'accept, x-auth-key, x-requested-with',
                $ENV{HTTP_ACCESS_CONTROL_ALLOW_CREDENTIALS} // 'true',
                'X-Auth-Key',
            );
        }
    }
    
    my $plusheaders = join '', map { "$_: $headers{$_}\r\n" } keys %headers;
    warn sprintf($rheaders,$code,status_message($code),$clen), $plusheaders, EOR;
    print sprintf($rheaders,$code,status_message($code),$clen), $plusheaders, EOR;
    #print STDERR sprintf($rheaders,$code,status_message($code),$clen), $plusheaders, EOR;

    1;
}

sub r_needauth
{
    sendheaders HTTP_FORBIDDEN, undef,
        'X-Auth-Url' => '/dns/auth',
        'X-Auth-Params' => 'U,SHA1(P)',
        @_;
}
sub setup_handlers
{
    no strict 'refs';
    my $pkg = ref($_[0]);
    map { ${$pkg.'::'}{$_} } grep { /^rh_z/ } keys %{$pkg.'::'};
}

sub handlers :lvalue
{
    $_[0]->{handlers} = $_[1] if defined $_[1];
    return $_[0]->{handlers};
}
sub run
{
    my ($self) = @_;
    return &r_badrequest if $ENV{REQUEST_METHOD} eq 'POST' and not defined($ENV{CONTENT_LENGTH});
    if($ENV{REQUEST_METHOD} eq 'OPTIONS') {
        warn "AUTH: OPTIONS matched $ENV{HTTP_ORIGIN}";
        return r_needauth() unless defined $ENV{HTTP_ORIGIN};
        my ($origin) = ($ENV{HTTP_ORIGIN}=~/http:\/\/([^\/]+)/);
        return r_needauth() unless $origin ~~ @allowed_domains;
        my $credentials = $ENV{HTTP_ACCESS_CONTROL_ALLOW_CREDENTIALS} // 'true';
        sendheaders(
            200,
            undef,
            'Access-Control-Allow-Origin' => $ENV{HTTP_ORIGIN},
            'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS',
            'Access-Control-Allow-Headers' => $ENV{HTTP_ACCESS_CONTROL_REQUEST_HEADERS} // 'accept, x-auth-key, x-requested-with',
            'Access-Control-Allow-Credentials' => $credentials,
            'Access-Control-Expose-Headers' => 'X-Auth-Key',
        );
        return 1;
    }

    foreach my $h (@{$self->handlers}) {
        #warn "TRY_RUN: $h";
        my $status = &$h(@_);
        return $status if $status;
    }
    #warn "RUN_DEFAULT_HANDLER!!!!";
    return &default_handler(@_);
    die;
}

sub parse0
{
    sysread STDIN, my $buf = '', $ENV{CONTENT_LENGTH};
    return undef unless length($buf) == $ENV{CONTENT_LENGTH};
    #warn "JSON_STRING: " . $buf;
    return decode_json($buf);
}

sub r_badrequest { sendheaders($_[0] // 400);}


1;
