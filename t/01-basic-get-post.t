use Test::More;
use Test::LWP::UserAgent;
use Test::Deep;
use Net::HTTP::Knork;
use Net::HTTP::Knork::Response;
use FindBin qw($Bin);
my $tua = Test::LWP::UserAgent->new;
$tua->map_response(
    sub {
        my $req = shift;
        my $uri_path = $req->uri->path;
        if ( $req->method eq 'GET' ) {
            return ( $uri_path eq '/show/foo' );
        }
        if ( $req->method eq 'POST' ) {
            if ( $uri_path eq '/add' ) {
                my $content = $req->content;
                return eq_deeply( $content,
                    { titi => 'toto', tutu => 'plop' } );
            }
        }
    },
    Net::HTTP::Knork::Response->new('200','OK')
);
my $client = Net::HTTP::Knork->new(
    spore_rx => "$Bin/../share/config/specs/spore_validation.rx",
    spec     => 't/fixtures/api.json',
    client   => $tua
);


my $resp = $client->get_user_info( { user => 'foo' } );
is( $resp->code, '200', 'our user is correctly set to foo' );
$resp =
  $client->add_user( { payload => { 'titi' => 'toto', 'tutu' => 'plop' } } );
is( $resp->code, '200', 'our parameters are correctly set' );
done_testing();
