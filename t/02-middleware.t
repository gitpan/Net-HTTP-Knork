use Test::More;
use Test::LWP::UserAgent;
use Test::Deep;
use Net::HTTP::Knork;
use Net::HTTP::Knork::Response;
use FindBin qw($Bin);
use JSON;
my $tua = Test::LWP::UserAgent->new;

my $json = JSON->new->utf8(1)->allow_nonref;
$tua->map_response(
    sub {
        my $req = shift;
        if ( $req->method eq 'POST' ) {
            my $uri_path = $req->uri->path;
            if ( $uri_path eq '/add' ) {
                my $content = $json->decode( $req->content );
                return eq_deeply(
                    $content,
                    { titi => 'toto', tutu => 'plop' }
                );
            }
        }
    },
    Net::HTTP::Knork::Response->new(
        '200', 'OK',
        HTTP::Headers->new( 'Content-Type' => 'application/json' ),
        $json->encode( { msg => 'resp is ok' } )
    )
);

my $client = Net::HTTP::Knork->new(
    spore_rx => "$Bin/../share/config/specs/spore_validation.rx",
    spec     => 't/fixtures/api.json',
    client   => $tua
);

$client->add_middleware(
    {   on_request => sub {
            my $self = shift;
            my $req = shift;
            $req->header( 'Content-Type' => 'application/json' );
            $req->header( 'Accept'       => 'application/json' );
            $req->content( $json->encode( $req->content ) );
            return $req;
        },
        on_response => sub {
            my $self = shift;
            my $resp = shift;
            $resp->content( $json->decode( $resp->content ) );
            return $resp;
          }
    }
);


$resp =
  $client->add_user( { payload => { 'titi' => 'toto', 'tutu' => 'plop' } } );
is( $resp->code, '200', 'request was correctly encoded' );
cmp_deeply( $resp->content, { msg => 'resp is ok' }, 'resp was correctly decoded' );
done_testing();
