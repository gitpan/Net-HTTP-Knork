package Net::HTTP::Knork;

# ABSTRACT: Lightweight implementation of Spore specification
use Moo;
use Sub::Install;
use Try::Tiny;
use Carp;
use JSON;
use Data::Rx;
use LWP::UserAgent;
use URI;
use File::ShareDir ':ALL';
use Subclass::Of;
use Net::HTTP::Knork::Request;
use Net::HTTP::Knork::Response;

with 'Net::HTTP::Knork::Role::Middleware';


has 'client' => ( is => 'lazy', );

# option that allows one to pass optional parameters that are not specified
# in the spore 'optional_params' section for a given method

has 'lax_optionals' => ( is => 'rw', default => sub {0} );

has 'base_url' => (
    is      => 'rw',
    lazy    => 1,
    builder => sub {
        return $_[0]->spec->{base_url};
    }
);

has 'request' => (
    is      => 'rw',
    lazy    => 1,
    clearer => 1,
    builder => sub {
        return Net::HTTP::Knork::Request->new( $_[0]->env );
    }
);

has 'env' => ( is => 'rw', );

has 'spec' => (
    is       => 'lazy',
    required => 1,
    coerce   => sub {
        my $json_spec = $_[0];
        my $spec;

        # it could be a file
        try {
            open my $fh, '<', $json_spec or croak 'Cannot read the spec file';
            local $/ = undef;
            binmode $fh;
            $spec = from_json(<$fh>);
            close $fh;
        }
        catch {
            try {
                $spec = from_json($json_spec);
            }

            # it is not json, so we are returning the string as is
            catch {
                $spec = $json_spec;
            };
        };
        return $spec;
    }
);

has 'default_params' => (
    is        => 'rw',
    default   => sub { {} },
    predicate => 1,
    clearer   => 1,
    writer    => 'set_default_params',
);

has 'spore_rx' => (
    is      => 'rw',
    default => sub {
        return dist_file(
            'Net-HTTP-Knork',
            'config/specs/spore_validation.rx'
        );
    }
);

has 'http_options' => (
    is      => 'rw',
    default => sub { {} },
);

# Change the namespace of a given instance, so that there won't be any
# method collision between two instances

sub BUILD {
    my $self     = shift;
    my $subclass = subclass_of('Net::HTTP::Knork');
    bless( $self, $subclass );
    $self->build_from_spec();
}

sub _build_client {
    my $self = shift;
    return LWP::UserAgent->new( %{ $self->http_options } );
}

sub validate_spore {
    my ( $self, $spec ) = @_;
    my $rx = Data::Rx->new;
    my $spore_schema;
    if ( -f $self->spore_rx ) {
        open my $fh, "<", $self->spore_rx;
        binmode $fh;
        local $/ = undef;
        $spore_schema = <$fh>;
        close $fh;
    }
    else {
        croak "Spore schema " . $self->spore_rx . " could not be found";
    }
    my $json_schema = from_json($spore_schema);
    my $schema      = $rx->make_schema($json_schema);
    try {
        my $valid = $schema->assert_valid($spec);
    }
    catch {
        croak "Spore specification is invalid, please fix it\n" . $_;
    };
}

# take a spec and instanciate methods that matches those

sub build_from_spec {
    my $self = shift;
    my $spec = $self->spec;

    $self->validate_spore($spec);
    my $base_url = $self->base_url;
    croak
      'We need a base URL, either in the spec or as a parameter to build_from_spec'
      unless $base_url;
    $self->build_methods();
}

sub build_methods {
    my $self = shift;
    foreach my $method ( keys %{ $self->spec->{methods} } ) {
        my $sub_from_spec =
          $self->make_sub_from_spec( $self->spec->{methods}->{$method} );
        Sub::Install::install_sub(
            {   code => $sub_from_spec,
                into => ref($self),
                as   => $method,
            }
        );
    }
}

sub make_sub_from_spec {
    my $reg       = shift;
    my $meth_spec = shift;
    return sub {
        my $self = shift;
        $self->clear_request;
        my $ref_param_spec = shift // {};
        my %param_spec = %{$ref_param_spec};
        if ( $self->has_default_params ) {
            foreach my $d_param ( keys( %{ $self->default_params } ) ) {
                $param_spec{$d_param} = $self->default_params->{$d_param};
            }
        }
        my %method_args = %{$meth_spec};
        my $method      = $method_args{method};
        my $payload =
          ( defined $param_spec{spore_payload} )
          ? delete $param_spec{spore_payload}
          : delete $param_spec{payload};

        if ( $method_args{required_payload} && !$payload ) {
            croak "this method requires a payload and no payload is provided";
        }
        if ( $payload
            && ( $method !~ /^(?:POST|PUT|PATCH)$/i ) )
        {
            croak "payload requires a PUT, PATCH or POST method";
        }

        $payload //= undef;

        if ( $method_args{required_params} ) {
            foreach my $required ( @{ $method_args{required_params} } ) {
                if ( !grep { $required eq $_ } keys %param_spec ) {
                    croak
                      "Parameter '$required' is marked as required but is missing";
                }
            }
        }

        my $params;
        foreach ( @{ $method_args{required_params} } ) {
            push @$params, $_, delete $param_spec{$_};
        }

        foreach ( @{ $method_args{optional_params} } ) {
            push @$params, $_, delete $param_spec{$_}
              if ( defined( $param_spec{$_} ) );
        }
        if (%param_spec) {
            if ( $self->lax_optionals ) {
                foreach ( keys %param_spec ) {
                    push @$params, $_, delete $param_spec{$_};
                }
            }
        }

        my $base_url = URI->new( $self->base_url );
        my $env      = {
            REQUEST_METHOD => $method,
            SERVER_NAME    => $base_url->host,
            SERVER_PORT    => $base_url->port,
            SCRIPT_NAME    => (
                $base_url->path eq '/'
                ? ''
                : $base_url->path
            ),
            PATH_INFO       => $method_args{path},
            REQUEST_URI     => '',
            QUERY_STRING    => '',
            HTTP_USER_AGENT => $self->client->agent // '',

            'spore.params'     => $params,
            'spore.payload'    => $payload,
            'spore.errors'     => *STDERR,
            'spore.url_scheme' => $base_url->scheme,
            'spore.userinfo'   => $base_url->userinfo,

        };
        $self->env($env);
        my $request      = $self->request->finalize();
        my $raw_response = $self->perform_request($request);
        return $self->generate_response($raw_response);
    };
}


sub perform_request {
    my $self    = shift;
    my $request = shift;
    return $self->client->request($request);
}

sub generate_response {
    my $self           = shift;
    my $raw_response   = shift;
    my $prev_response  = shift;
    my $knork_response = $self->request->new_response(
        $raw_response->code, $raw_response->message, $raw_response->headers,
        $raw_response->content
    );
    if ( defined($prev_response) ) {
        $knork_response->raw_body( $prev_response->content )
          unless defined( ( $knork_response->raw_body ) );
    }
    return $knork_response;
}



1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::HTTP::Knork - Lightweight implementation of Spore specification

=head1 VERSION

version 0.09

=head1 SYNOPSIS 

    use strict; 
    use warnings; 
    use Net::HTTP::Knork;
    use JSON;
    my $spec = to_json(
        {   version => 1,
            format  => [ "json", ],
            methods => {
                test => {
                    method => 'GET',
                    path   => '/test/:foo',
                    required_params => [ "foo" ],
                }
            }
            base_url => 'http://example.com',
        }
    );

    my $knork = Net::HTTP::Knork->new(spec => $spec);

    # make a GET to 'http://example.com/test/bar'
    my $resp = $knork->test({ foo => bar}); 

=head1 DESCRIPTION 

Net::HTTP::Knork is a module that aims to be compatible with L<the Spore specification|https://github.com/SPORE/specifications/blob/master/spore_description.pod>. 
So it is like L<Net::HTTP::Spore> but with some differences. 

=head2 Moo !

When I was working with Net::HTTP::Spore, I found it hard to get around all the magic done with Moose. 
So this implementation aims at having something more lightweight.

=head2 Specifications

Specifications can be written either in a JSON file, string, or as a pure Perl hash.
On top of that, every specification passed is validated against the Spore specification, using L<Data::Rx>.

=head2 No middlewares 

This module does not provide middlewares as in L<Net::HTTP::Spore>, but there are some ways around it that should fit basic needs. 
See Middlewares below

=head2 HTTP::Response compliant 

All the responses returned by Knork are objects from a class extending L<HTTP::Response>. 
This means that you can basically manipulate any response returned by a Knork client as an HTTP::Response.

=head2 Always check your HTTP codes !

No assumptions are made regarding the responses you may receive from an API. 
It means that, contrary to L<Net::HTTP::Spore>, the code won't just die if the API returns a 4XX. This also implies that you should always check the responses returned. 

=head1 METHODS

=over

=item new 

Creates a new Knork object.  

    my $client = Net::HTTP::Knork->new(spec => '/some/file.json');
    # or 
    my $client = Net::HTTP::Knork->new(spec => $a_perl_hash); 
    # or 
    my $client = Net::HTTP::Knork->new($spec => $a_json_object);

Other constructor options: 

=over

=item default_params:  

hash specifying default parameters to pass on every requests.

    # pass foo=bar on every request 
    my $client = Net::HTTP::Knork->new(spec => 'some_file.json', default_params => {foo => bar}); 

=item client: 
a L<LWP::UserAgent> HTTP client. Automatically created if not passed. 

=item http_options: 
options to pass to the L<LWP::UserAgent> used as a backend for Knork. 

=back

=item make_sub_from_spec 

Creates a new Knork sub from a snippet of spec.
You might want to do that if you want to create new subs with parameters you can get on runtime, while maintaining all the benefits of using Knork. 

    my $client = Net::HTTP::Knork->new(spec => '/some/file.json');
    my $response = $client->get_foo_url(); 
    my $foo_url = $response->body->{foo_url}; 
    my $post_foo = $client->make_sub_from_spec({method => 'POST', path => $foo_url});
    $client->$post_foo(payload => { bar => 'baz' });

=back

=head1 MIDDLEWARES 

=head2 Usage 

    use strict; 
    use warnings; 
    use JSON; 
    use Net::HTTP::Knork; 
    # create a client with a middleware that encode requests to json and
    # decode responses from json 
    my $client = Net::HTTP::Knork->new(spec => '/path/to/spec.json');
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

Although middlewares cannot be created as in L<Net::HTTP::Spore>, there is still the possibility to declare subs that will be executed either on requests or responses. 
To accomplish this, it installs modifiers around some core functions in L<Net::HTTP::Knork>, using L<Class::Method::Modifiers>.

=head2 Limitations 

=over

=item Basic 

The system is kind of rough on edges. It should match simple needs, but for complex middlewares it would need a lot of code. 

=item Order of application 

The last middleware applicated will always be the first executed. 

=back

=head1 TESTING

As a HTTP client can be specified as a parameter when building a Net::HTTP::Knork client, this means that you can use L<Test::LWP::UserAgent> to test your client. This is also how tests for Net::HTTP::Knork are implemented. 

    use Test::More;
    use Test::LWP::UserAgent;
    use Net::HTTP::Knork;
    use Net::HTTP::Knork::Response;
    my $tua = Test::LWP::UserAgent->new;
    $tua->map_response(
        sub {
            my $req = shift;
            my $uri_path = $req->uri->path;
            if ( $req->method eq 'GET' ) {
                return ( $uri_path eq '/show/foo' );
            }
        },
        Net::HTTP::Knork::Response->new('200','OK')
    );
    my $client = Net::HTTP::Knork->new(
        spec => {
            base_url => 'http://example.com',
            name     => 'test',
            methods  => [
                {   get_user_info => { method => 'GET', path => '/show/:user' }
                }
            ]
        },
        client => $tua
    );


    my $resp = $client->get_user_info( { user => 'foo' } );
    is( $resp->code, '200', 'our user is correctly set to foo' );

=head1 TODO 

This is still early alpha code but there are still some things missing : 

=over

=item debug mode

=item more tests 

=item a real life usage

=back

=head1 BUGS

This code is early alpha, so there will be a whole bucket of bugs.

=head1 ACKNOWLEDGEMENTS 

Many thanks to Franck Cuny, the originator of L<Net::HTTP::Spore>. Some parts of this module borrow code from his module. 

=head1 SEE ALSO 

L<Net::HTTP::Spore>

=head1 AUTHOR

Emmanuel Peroumalnaïk

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by E. Peroumalnaik.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
