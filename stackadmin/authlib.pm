package stackadmin::authlib;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/gen_authkey check_authkey packip/;



use Crypt::Rijndael;
use Crypt::OpenSSL::Random;
use Crypt::Random qw/makerandom_octet/;
use Socket qw/AF_INET AF_INET6 inet_pton inet_ntop/;
use JSON::XS;
use MIME::Base64;

sub gen_iv { makerandom_octet(Length => 16, Strength => 0); }
sub hexpack { join '', unpack('(H2)*', $_[0]) }
sub hex2bin { pack('C*', map { hex $_ } unpack("(A2)*", $_[0])) }

sub K
{
    my ($k, $iv, $len) = @_;                                                                                                                                                                   
    die "crypt error" unless $len % 16 == 0 and length($k) == $len and length($iv) == $len;
    my $sz = $len / 4;
    my @bk = unpack("N$sz", $k);
    my @ivk = unpack("N$sz", $iv);
    return join '', $k, pack("N$sz", (map { $bk[$_] ^ $ivk[$_] } (0..$sz-1)));
}

sub gen_kf(&)
{
    my ($f) = @_;
    my $key = "\x9f8|O>.\x02h\x8en\xf8\n\x9b\x94\xb8R";
    return sub { $f->($key, @_); }
}

#my $gen_auth_key = gen_kf {
*gen_authkey = gen_kf {
    #key format: uid(4) + exptime(4) + ip(16) + pad(8)
    #key algorithm: 
    # - lookup iv for uid
    # - encrypt key with user's iv
    # - add BE-packed uid
    # - encode base64
    # - replace LF with $
    #final_len = 49bytes
    #TODO: add CRC?
    #my($key,$uid, $db) = @_;
    my($key, $iv, $uid, $ip) = @_;
    $iv = hex2bin($iv);
    my $c = Crypt::Rijndael->new(K($key,$iv,16), Crypt::Rijndael::MODE_CBC());
    $c->set_iv($iv);
    my $pad = makerandom_octet(Length => 8, Strength => 0);
    my $exptime = time + 86400;
    my $data = pack('I!I!a16a8', $uid, $exptime, $ip, $pad);
    my $encdata = encode_base64(join('', $c->encrypt($data), pack('N', $uid)));
    $encdata=~s/\n/\$/sg;
    return $encdata;
};

*check_authkey = gen_kf {
    my($key, $authkey, $iv, $uid) = @_;
    $iv = hex2bin($iv);
    my $c = Crypt::Rijndael->new(K($key,$iv,16), Crypt::Rijndael::MODE_CBC());
    $c->set_iv($iv);
    my($kuid,$exptime,$kip,$pad) = unpack('I!I!a16a8', $c->decrypt($authkey));
    my $ip = $ENV{REMOTE_ADDR} // '127.0.0.1';
    $ip = "::ffff:$ip" unless $ip=~/:/;
    return undef unless $kip eq inet_pton(AF_INET6, $ip);
    return undef unless $kuid == $uid;
    return undef unless time < $exptime;
    return 1;
    
};

sub packip
{
    my $ip = $ENV{REMOTE_ADDR} // '127.0.0.1';
    $ip = "::ffff:$ip" unless $ip=~/:/;
    return inet_pton(AF_INET6, $ip);
}



1;
