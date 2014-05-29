#!/usr/bin/env perl
#__author__: 'system fault' <sysfault@yahoo.com> [http://sclerosys.com/nginx-fastcgid]
#
#TODO: update to support namespaced apps (apps::myapp) as arguments
#

use v5.18;

my $cfpfx = 'fastcgi-';
my $ngxcf = $ENV{FASTCGI_CONF} // '/etc/nginx/fastcgipl-upstreams.conf';
my $revivify = 1;
my $forkthunder_time_threshold = 2;
my $forkthunder_restart_threshold = 1;

defined (my $appname = $ARGV[0]) or die "missing app name";

#eval "require $appname";
#die $@ if $@;

-f $ngxcf or die "can't find nginx fastcgi upstreams config file ($ngxcf)";

use File::Basename;
use File::Spec::Functions;
use syslinux qw/epoll signalfd/;
use Data::Dumper;

my $fastcgi_program = $ENV{FASTCGI_PROGRAM} // catfile(dirname($0), 'fastcgi.pl');
die "no fastcgi program found ($fastcgi_program)" unless -x $fastcgi_program;

my %pmap = ();

my $ep = syslinux::epoll->new();

my %sighandlers = (
    HUP => sub {
        say "SIGHUP: restarting service";
        &restart;
        #print Dumper \%pmap;
    },
    TERM => sub {
        say "SIGTERM: stopping service";
        &stop;
        say "exiting";
        exit 0;
    },
    CHLD => sub {
        say "SIGCHLD received, ignoring: PIPE_READ0_WAIT";
        #print Dumper $_[0];
    },
    USR1 => sub {
        say "condrestart: testing config updates";
    },
    INT => sub {
        say "SIGINT: stopping service";
        &stop;
        say "exiting";
        exit 0;
    },
);

my ($sigfd, $oldmask) = signalfd(-1, SFD_CLOEXEC|SFD_NONBLOCK, keys %sighandlers);

$ep->add($sigfd, EPOLLIN, sub {
    my($ev, $fh) = @_;
    die $! unless $ev == EPOLLIN and fileno($fh) == fileno($sigfd);
    my @sigs = sigread($fh);
    foreach my $sig (@sigs) {
        say "SIGNAL_CODE: " . $sig->{signo};
        say "SIGNAL_NAME: " . $SIGv2n{$sig->{signo}};
        next unless defined $sighandlers{$SIGv2n{$sig->{signo}}};
        $sighandlers{$SIGv2n{$sig->{signo}}}->($sig);
    }
});

&start;
&waitforevents;


sub startchild
{
    my ($loc) = @_;
    my ($p0, $p1);
    pipe($p0, $p1) or die $!;
    my $pid;
    die $! unless defined(my $pid = fork());
    if($pid == 0) {
        close $p0;
        POSIX::dup2(fileno($p1), fileno(STDERR));
        sigprocmask(&POSIX::SIG_SETMASK, $oldmask, undef);
        $ENV{FCGIADDR} = $loc;
        #$ENV{LOGFD} = fileno $p1;
        exec $fastcgi_program;
    }
    say "UPSTREAM_STARTED: $pid => $loc \"$fastcgi_program $loc $appname\"";
    close $p1;
    $ep->add($p0, EVREAD, sub {
        my ($ev, $fh) = @_;
        if($ev != EVREAD) {
            &reapchild($pid);
            return;
        }
        sysread($fh, my $buf = '', 8192);
        unless(length($buf) > 0) {
            &reapchild($pid);
            return;
        }
        join '', $buf, "\n" unless $buf=~/\n$/;
        print "LOG($pid,$loc): $buf";
    });
    return ($pid, $p0, time, 0);
}

use constant {
    PID=>0, PIPE=>0, LOC=>1, CTIME=>2,RSTART=>3
};

sub reapchild
{
    my $now = time;
    my $pinf = delete $pmap{$_[PID]};
    die "uh-oh. can't find pid $_[0] in pmap map" unless defined $pinf;
    warn "reapchild: reaping pid $_[0]";
    waitpid($_[PID], 0);
    $pinf->[RSTART] += 1;
    close $pinf->[PIPE];
    if( (($now - $pinf->[CTIME]) <= $forkthunder_time_threshold) and 
        ($pinf->[RSTART] >= $forkthunder_restart_threshold)) {
        warn "(un)restart thresholds met, won't reload a new kid";
        return;
    }
    return unless $revivify;
    my ($pid, $p0, $ctime, $restarts) = &startchild($pinf->[LOC]);
    $restarts += $pinf->[RSTART];
    warn "child $_[0] (re)started on pipe " . fileno($p0);
    $pmap{$pid} = [$p0, $pinf->[1], time, $restarts];
}

sub start
{
    foreach my $loc (&parse_config) {
        my ($pid, $p0, $ctime, $restarts) = &startchild($loc);
        say "child $pid started on pipe " . fileno($p0);
        $pmap{$pid} = [$p0, $loc, $ctime, $restarts];
    }
    die "no nginx config found for app $appname" unless scalar(keys %pmap) > 0;
}

sub stop 
{
    say "stopping service";
    while(my($pid,$inf) = each(%pmap)) {
        say "terminating child $pid ...";
        kill 'TERM', $pid;
        close $inf->[PIPE];
    }
    say "reaping zombies ...";
    while(1) {
        my $pid = waitpid(-1,0);
        last if $pid < 0;
        delete $pmap{$pid};
        say "zombie $pid reaped out";
    }
    say "ERROR! garbage in pmap!" if scalar(keys(%pmap)) > 0;
    say "service stoped";
}

sub restart 
{
    say "stopping service ...";
    &stop;
    say "settling down...";
    $ep->wait(2);
    say "starting service ...";
    &start;
}

sub waitforevents { return $ep->wait(@_); }




use constant {MATCH_UPSTREAM=>0, MATCH_SERVERS=>1};

sub parse_config
{
    my @upstreams = ();

    open my $cf = undef, '<', $ngxcf or die $!;
    my $state = MATCH_UPSTREAM;
    while(<$cf>) {
        chomp;
        s/^\s*//;
        s/;\s*//;
        if ($state == MATCH_UPSTREAM) {
            next unless /^\s*upstream\s+$cfpfx$appname\s+{/;
            $state = MATCH_SERVERS;
            next;
        }
        if($state == MATCH_SERVERS) {
            if((my ($match) = ($_=~/^\s*server\s+(.*)/))) {
                my @spec = split /\s+/, $match;
                $spec[0]=~s/^unix://;
                push @upstreams, $spec[0];
                last if $spec[$#spec]=~/}/;
            }
            last if /}/;
        }
    }
    return @upstreams;
}
