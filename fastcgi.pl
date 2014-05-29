#!/usr/bin/env perl

use FCGI;
use v5.18;
use IO::Handle;
BEGIN 
{
    #TODO: move attribute decls in BEGIN fase :ATTR(CODE,BEGIN)
    #eval "require $ENV{FCGIAPP}";
}

#my ($port,$app) = ($ARGV[0], $ARGV[1]);
my ($port, $app) = map { $ENV{$_} } (qw/FCGIADDR FCGIAPP/);

die "missing parameters" unless defined $port and defined $app;
eval "require $app";
die $@ if $@;
warn "PORT=$port";
unlink $port if -S $port;
#umask 0177;
umask 0111;
use POSIX;
POSIX::setuid($ENV{FCGIUID}+0);

my $handler = $app->new();
#warn "UPSTREAM($port,$handler): OK\@$$";
#print STDERR "handler at $handler";

my $socket = FCGI::OpenSocket( "$port", 64 );

$SIG{INT} = sub {
    $handler->terminate;
    FCGI::CloseSocket($socket);
    exit 0;
};
die "can't bind: $!" unless defined $socket;
my $request = FCGI::Request( \*STDIN, \*STDOUT, IO::Handle->new,
    \%ENV, $socket );
warn "UPSTREAM_UP_OK(handler=$handler, \@($port,$$)";
while($request->Accept() >= 0) {
    my $mod = $handler->lookup();
    $mod->run();
    $mod->reset();
    #my $mod = $handler->run();
    #$mod->reset();
    #$request->Flush;
}
$handler->serve() while $request->Accept() >= 0;
die "FUCKIT $!";
#exit 0;

