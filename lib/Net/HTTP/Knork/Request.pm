package Net::HTTP::Knork::Request;

# ABSTRACT: HTTP request object from SPORE env hash

use Moo;
use Carp;
use URI;
use HTTP::Headers;
use HTTP::Request;
use URI::Escape;
use MIME::Base64;
use Net::HTTP::Knork::Response;

has env => (
    is       => 'rw',
    required => 1,
    default => sub { { } },
);

sub get_from_env { 
    return $_[0]->env->{$_[1]};
}

sub set_to_env { 
    $_[0]->env->{$_[1]} = $_[2];
}

has path => (
    is      => 'rw',
    lazy    => 1,
    default => sub { $_[0]->env->{PATH_INFO} }
);

has headers => (
    is      => 'rw',
    lazy    => 1,
    handles => {
        header => 'header',
    },
    default => sub {
        my $self = shift;
        my $env  = $self->env;
        my $h    = HTTP::Headers->new(
            map {
                ( my $field = $_ ) =~ s/^HTTPS?_//;
                ( $field => $env->{$_} );
              } grep { /^(?:HTTP|CONTENT)/i } keys %$env
        );
        return $h;
    },
);

sub BUILDARGS {
    my $class = shift;

    if (@_ == 1 && !exists $_[0]->{env}) {
        return {env => $_[0]};
    }
    return @_;
}

sub method {
    my ( $self, $value ) = @_;
    if ($value) {
        $self->set_to_env( 'REQUEST_METHOD', $value );
    }
    else {
        return $self->get_from_env('REQUEST_METHOD');
    }
}

sub host {
    my ($self, $value) = @_;
    if ($value) {
        $self->set_to_env('SERVER_NAME', $value);
    }else{
        return $self->get_from_env('SERVER_NAME');
    }
}

sub port {
    my ( $self, $value ) = @_;
    if ($value) {
        $self->set_to_env( 'SERVER_PORT', $value );
    }
    else {
        return $self->get_from_env('SERVER_PORT');
    }
}

sub script_name {
    my ( $self, $value ) = @_;
    if ($value) {
        $self->set_to_env( 'SCRIPT_NAME', $value );
    }
    else {
        return $self->get_from_env('SCRIPT_NAME');
    }
}

sub request_uri {
    my ($self, $value) = @_;
    if ($value) {
        $self->set_to_env( 'REQUEST_URI', $value );
    }
    else {
        return $self->get_from_env('REQUEST_URI');
    }
}

sub scheme {
    my ($self, $value) = @_;
    if ($value) {
        $self->set_to_env( 'spore.url_scheme', $value );
    }
    else {
        return $self->get_from_env('spore.url_scheme');
    }
}

sub logger {
    my ($self, $value) = @_;
    if ($value) {
        $self->set_to_env( 'sporex.logger', $value );
    }
    else {
        return $self->get_from_env('sporex.logger');
    }
}

sub body {
    my ($self, $value) = @_;
    if ($value) {
        $self->set_to_env( 'spore.payload', $value );
    }
    else {
        return $self->get_from_env('spore.payload');
    }
}

sub base {
    my $self = shift;
    URI->new( $self->_uri_base )->canonical;
}

sub input   { (shift)->body(@_) }
sub content { (shift)->body(@_) }
sub secure  { $_[0]->scheme eq 'https' }

# TODO
# need to refactor this method, with path_info and query_string construction
sub uri {
    my ($self, $path_info, $query_string) = @_;

    if ( !defined $path_info || !defined $query_string ) {
        my @path_info = $self->_path;
        $path_info    = $path_info[0] if !$path_info;
        $query_string = $path_info[1] if !$query_string;
    }

    my $base = $self->_uri_base;

    my $path_escape_class = '^A-Za-z0-9\-\._~/';

    my $path = URI::Escape::uri_escape($path_info || '', $path_escape_class);

    if (defined $query_string && length($query_string) > 0) {
        $path .= '?' . $query_string;
    }

    $base =~ s!/$!! if $path =~ m!^/!;
    return URI->new( $base . $path )->canonical;
}

sub _path {
    my $self = shift;

    my $query_string;
    my $path = $self->env->{PATH_INFO};
    my @params = @{ $self->env->{'spore.params'} || [] };

    my $j = 0;
    for (my $i = 0; $i < scalar @params; $i++) {
        my $key = $params[$i];
        my $value = $params[++$i];
        if (!$value) {
            $query_string .= $key;
            last;
        }
        unless ( $path && $path =~ s/\:$key/$value/ ) {
            $query_string .= $key . '=' . $value;
            $query_string .= '&' if $query_string && scalar @params;
        }
    }

    $query_string =~ s/&$// if $query_string;
    return ( $path, $query_string );
}

sub _uri_base {
    my $self = shift;
    my $env  = $self->env;

    my $uri =
      ( $env->{'spore.url_scheme'} || "http" ) . "://"
      . (
        defined $env->{'spore.userinfo'}
        ? $env->{'spore.userinfo'} . '@'
        : ''
      )
      . (
        $env->{HTTP_HOST}
          || (( $env->{SERVER_NAME} || "" ) . ":"
            . ( $env->{SERVER_PORT} || 80 ) )
      ) . ( $env->{SCRIPT_NAME} || '/' );

    return $uri;
}

# stolen from HTTP::Request::Common
sub _boundary {
    my ( $self, $size ) = @_;

    return "xYzZy" unless $size;

    my $b =
      MIME::Base64::encode( join( "", map chr( rand(256) ), 1 .. $size * 3 ),
        "" );
    $b =~ s/[\W]/X/g;
    return $b;
}

sub _form_data {
    my ( $self, $data ) = @_;

    my $form_data;
    foreach my $k ( keys %$data ) {
        push @$form_data,
            'Content-Disposition: form-data; name="'
          . $k
          . '"'."\r\n\r\n"
          . $data->{$k};
    }

    my $b = $self->_boundary(10);
    my $t = [];
    foreach (@$form_data) {
        push @$t, '--', $b, "\r\n", $_, "\r\n";
    }
    push @$t, '--', $b, , '--', "\r\n";
    my $content = join("", @$t);
    return ($content, $b);
}

sub new_response {
    my $self = shift;
    my $res = Net::HTTP::Knork::Response->new(@_);
    $res->request($self);
    $res;
}

sub finalize {
    my $self = shift;

    my $path_info = $self->env->{PATH_INFO};

    my $form_data = $self->env->{'spore.form_data'};
    my $headers   = $self->env->{'spore.headers'};
    my $params    = $self->env->{'spore.params'} || [];

    my $query = [];
    my $form  = {};

    for ( my $i = 0 ; $i < scalar @$params ; $i++ ) {
        my $k = $params->[$i];
        my $v = $params->[++$i] // '';
        my $modified = 0;

        if ($path_info && $path_info =~ s/\:$k/$v/) {
            $modified++;
        }

        foreach my $f_k (keys %$form_data) {
            my $f_v = $form_data->{$f_k};
            if ($f_v =~ s/^\:$k/$v/) {
                $form->{$f_k} = $f_v;
                $modified++;
            }
        }

        foreach my $h_k (keys %$headers) {
            my $h_v = $headers->{$h_k};
            if ($h_v =~ s/^\:$k/$v/) {
                $self->header($h_k => $h_v);
                $modified++;
            }
        }

        if ($modified == 0) {
            if (defined $v) {
                push @$query, $k.'='.$v;
            }else{
                push @$query, $k;
            }
        }
    }

    # clean remaining :name in url
    $path_info =~ s/:\w+//g if $path_info;

    my $query_string;
    if (scalar @$query) {
        $query_string = join('&', @$query);
    }

    $self->env->{PATH_INFO}    = $path_info;
    $self->env->{QUERY_STRING} = $query_string;

    my $uri = $self->uri($path_info, $query_string || '');

    my $request = HTTP::Request->new(
        $self->method => $uri, $self->headers
    );

    if ( keys %$form_data ) {
        $self->env->{'spore.form_data'} = $form;
        my ( $content, $b ) = $self->_form_data($form);
        $request->content($content);
        $request->header('Content-Length' => length($content));
        $request->header(
            'Content-Type' => 'multipart/form-data; boundary=' . $b );
    }

    if ( my $payload = $self->content ) {
        $request->content($payload);
        $request->header(
            'Content-Type' => 'application/x-www-form-urlencoded' )
          unless $request->header('Content-Type');
    }

    return $request;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::HTTP::Knork::Request - HTTP request object from SPORE env hash

=head1 VERSION

version 0.09

=head1 SYNOPSIS

    use Net::HTTP::Knork::Request;

    my $request = Net::HTTP::Knork::Request->new($env);

=head1 DESCRIPTION

Net::HTTP::Knork::Request create a HTTP request
Based mostly on L<Net::HTTP::Spore::Request>, except that it uses Moo. 

=head1 METHODS

=over 4

=item new

    my $req = Net::HTTP::Knork::Request->new();

Creates a new Net::HTTP::Knork::Request object.

=item env

    my $env = $request->env;

Get the environment for the given request

=item method

    my $method = $request->method;

Get the HTTP method for the given request

=item port

    my $port = $request->port;

Get the HTTP port from the URL

=item script_name

    my $script_name = $request->script_name;

Get the script name part from the URL

=item path

=item path_info

    my $path = $request->path_info;

Get the path info part from the URL

=item request_uri

    my $request_uri = $request->request_uri;

Get the request uri from the URL

=item scheme

    my $scheme = $request->scheme;

Get the scheme from the URL

=item secure

    my $secure = $request->secure;

Return true if the URL is HTTPS

=item content

=item body

=item input

    my $input = $request->input;

Get the content that will be posted

=item query_string

=item headers

=item header

=item uri

=item query_parameters

=item base

=item new_response

=item finalize

=back

=head1 AUTHOR

Emmanuel Peroumalnaïk

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by E. Peroumalnaik.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
