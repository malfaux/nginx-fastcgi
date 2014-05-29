package stackadmin::code;
use v5.18;

use strict;
use warnings;
use base qw/stackadmin::webhandler/;
use stackadmin::webhandler;
use HTTP::Status qw/:constants :is status_message/;
use Git;

sub init
{
    my $repo = Git->repository(Directory => 
        '/var/www/stackadmin.com/dev/frontend');
    die "no git" unless defined $repo;
    $_[0]->{repo} = $repo;
}

sub rh_zcommit :REQUIRE_AUTH PATH('GET' => '^commit/?')
{
    my $repo = $_[0]->{repo};
    my @inf = $repo->command('log', '--name-status', 'HEAD^..HEAD');
    my $commit_id = (split /\s+/, $inf[0])[1];

    my @poll = $repo->command('pull');
    my $commit_id2 = $repo->command('rev-parse', 'HEAD');
    chomp $commit_id2;
    my $response = join "\n", "last commit information:\n", @inf, ">>>>>>>>>>pull result:>>>>>>>>>>>>\n", 
        @poll, "\n++++++++current commit id: $commit_id2",
                 "++++++++prev    commit id: $commit_id";

    sendheaders(HTTP_OK, length($response), 'Content-Type' => 'text/plain' );
    print $response;
    return 1;
}

1;
