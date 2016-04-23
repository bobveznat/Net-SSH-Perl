# $Id: Key.pm,v 1.20 2008/10/02 20:46:17 turnstep Exp $

package Net::SSH::Perl::Key;
use strict;
use warnings;

use Crypt::Digest::MD5 qw( md5 );
use Net::SSH::Perl::Buffer;

sub new {
    my $class = shift;
    if ($class eq __PACKAGE__) {
        $class .= "::" . shift();
        eval "use $class;";
        die "Key class '$class' is unsupported: $@" if $@;
    }
    my $key = bless {}, $class;
    my $comment = @_ == 2 ? pop @_ : undef;
    $key->init(@_);
    $key->comment($comment);
    $key;
}

use vars qw( %KEY_TYPES  @KEY_TYPES );
%KEY_TYPES = (
    'ssh-dss' => 'DSA',
    'ssh-rsa' => 'RSA',
    'ssh-ed25519' => 'Ed25519',
    'ecdsa-sha2-nistp256' => 'ECDSA',
);
# Search order list of the keys above for fast parsing
# of the authorized_keys files
@KEY_TYPES = grep { exists $KEY_TYPES{$_} } qw(
    ssh-rsa
    ssh-dss
    ssh-ed25519
    ecdsa-sha2-nistp256
);

sub new_from_blob {
    my $class = shift;
    my($blob) = @_;
    my $b = Net::SSH::Perl::Buffer->new( MP => 'SSH1' );
    $b->append($blob);
    my $ssh_name = $b->get_str;
    my $type = $KEY_TYPES{$ssh_name};
    __PACKAGE__->new($type, @_);
}

sub extract_public {
    my $class = shift;
    my($blob) = pop @_;
    my $expected_type = @_ ? shift : undef;

    # Locate the key-type in the blob.
    my $type;
    my $type_offset;
    foreach my $t (@KEY_TYPES) {
        $type_offset = index($blob,$t);
        if($type_offset >= 0) {
            $type = $t;
            last;
        }
    }
    if( !defined $type ) {
        warn "Invalid public key line, could not find type designation, searched for: " . join(', ', @KEY_TYPES);
        return;
    }
    # Check for options
    if( $type_offset > 0 ) {
        my $optstr = substr($blob,0,$type_offset,'');
        # TODO: Is it worthwhile to provide parsing/setting of SSH options through this interface
    }
    substr($blob,0,length($type)+1,'');

    my($data, $comment) = split /\s+/, $blob, 2;
    die "Invalid or unsupported key type: $type" unless exists $KEY_TYPES{$type};
    my $module = $KEY_TYPES{$type};
    warn "Requested type: $expected_type doesn't match actual type: '$module'" if defined $expected_type && $expected_type ne $module;
    eval "use MIME::Base64";
    die $@ if $@;
    __PACKAGE__->new($module, decode_base64($data), $comment);
}

BEGIN {
    no strict 'refs'; ## no critic
    for my $meth (qw( read_private keygen )) {
        *$meth = sub {
            my $class = shift;
            if ($class eq __PACKAGE__) {
                $class .= "::" . shift();
                eval "use $class;";
                die "Key class '$class' is unsupported: $@" if $@;
            }
            $class->$meth(@_);
        };
    }
}

use vars qw( %OBJ_MAP );
%OBJ_MAP = (
    'DSA PRIVATE KEY'  => [ 'DSA' ],
    'SSH2 ENCRYPTED PRIVATE KEY' => [ 'DSA', [ 'SSH2' ] ],
    'RSA PRIVATE KEY'  => [ 'RSA' ],
    'OPENSSH PRIVATE KEY'  => [ 'Ed25519' ],
);

sub read_private_pem {
    my $class = shift;
    my $keyfile = $_[0];
    open my $fh, '<', $keyfile or return;
    chomp(my $desc = <$fh>);
    close $fh or warn qq{Could not close "$keyfile": $!\n};
    return unless $desc;
    my($object) = $desc =~ /^-----?\s?BEGIN ([^\n\-]+)\s?-?----\s*$/;
    $object =~ s/\s*$//;
    my $rec = $OBJ_MAP{$object} or return;
    $class = __PACKAGE__ . "::" . $rec->[0];
    eval "use $class;";
    die "Key class '$class' is unsupported: $@" if $@;
    my @args = $rec->[1] ? @{ $rec->[1] } : ();
    $class->read_private(@_, @args);
}

sub init;
sub extract_public;
sub dump_public;
sub as_blob;
sub equal;
sub size { undef };

sub comment {
    my $self = shift;
    my $comment = shift;
    if( defined $comment and length $comment ) {
        $self->{comment} = $comment;
    }
    return exists $self->{comment} ? $self->{comment} : undef;
}

sub fingerprint {
    my $key = shift;
    my($type) = @_;
    my $data = $key->fingerprint_raw;
    $type && $type eq 'bubblebabble' ?
        _fp_bubblebabble($data) : _fp_hex($data);
}

sub _fp_bubblebabble {
    eval "use Digest::BubbleBabble qw( bubblebabble )";
    die "Can't load BubbleBabble implementation: $@" if $@;
    eval "use Crypt::Digest::SHA1 qw( sha1 )";
    die "Can't load SHA1: $@" if $@;
    bubblebabble( Digest => sha1($_[0]) )
}

sub _fp_hex { join ':', map { sprintf "%02x", ord } split //, md5($_[0]) }

1;
__END__

=head1 NAME

Net::SSH::Perl::Key - Public or private key abstraction

=head1 SYNOPSIS

    use Net::SSH::Perl::Key;
    my $key = Net::SSH::Perl::Key->new;

=head1 DESCRIPTION

I<Net::SSH::Perl::Key> implements an abstract base class interface
to key objects (either DSA, RSA, or Ed25519 keys, currently). The
underlying implementation for RSA is an internal, hash-reference
implementation.  The DSA implementation uses I<Crypt::DSA>, and
the Ed25519 implementation uses I<Crypt::Ed25519>.

=head1 USAGE

=head2 Net::SSH::Perl::Key->new($key_type [, $blob [, $compat_flag_ref ]])

Creates a new object of type I<Net::SSH::Perl::Key::$key_type>,
after loading the class implementing I<$key_type>. I<$key_type>
should be C<DSA>, C<RSA1>, or C<Ed25519>.

I<$blob>, if present, should be a string representation of the key,
from which the key object can be initialized. In fact, it should
be the representation that is returned from the I<as_blob> method,
below.

I<$compat_flag_ref> should be a reference to the SSH compatibility
flag, which is generally stored inside of the I<Net::SSH::Perl>
object. This flag is used by certain key implementations (C<DSA>)
to work around differences between SSH2 protocol implementations.

Returns the new key object, which is blessed into the subclass.

=head2 Net::SSH::Perl::Key->read_private($key_type, $file [, $pass])

Reads a private key of type I<$key_type> out of the key file
I<$file>. If the private key is encrypted, an attempt will be
made to decrypt it using the passphrase I<$pass>; if I<$pass>
is not provided, the empty string will be used. An empty
passphrase can be a handy way of providing password-less access
using publickey authentication.

If for any reason loading the key fails, returns I<undef>; most
of the time, if loading the key fails, it's because the passphrase
is incorrect. If you first tried to read the key using an empty
passphrase, this might be a good time to ask the user for the
actual passphrase. :)

Returns the new key object, which is blessed into the subclass
denoted by I<$key_type> (either C<DSA>, C<RSA1> or C<Ed25519>).

=head2 Net::SSH::Perl::Key->keygen($key_type, $bits)

$key_type is either RSA or DSA.  Generates a new DSA or RSA key
and returns that key. The key returned is the private key, which
(presumably) contains all of the public key data, as well. I<$bits>
 is the number of bits in the key.

Your I<$key_type> implementation may not support key generation;
if not, calling this method is a fatal error.

Returns the new key object, which is blessed into the subclass
denoted by I<$key_type> (either C<DSA> or C<RSA1>).

=head2 Net::SSH::Perl::Key->keygen('Ed25519' [,$comment])

Generates a new Ed25519 key with an optional comment.

Returns the new key object, which is bless into the Ed25519
subclass.

=head2 Net::SSH::Perl::Key->extract_public([$key_type,] $key_string)

Given a key string I<$key_string>, which should be a textual
representation of the public portion of a key, extracts the key
attributes out of that string.  This is used to extract public keys out
of entries in F<known_hosts> and public identity files.

Returns the new key object, which is blessed into the subclass
determined by reading the I<$key_string>.

Throws a warning if the optional parameter I<$key_type> passed in
mismatches the determined key type.


=head2 $key->write_private([ $file [, $pass, $ciphername, $rounds] ])

Writes out the private key I<$key> to I<$file>, and encrypts
it using the passphrase I<$pass>. If I<$pass> is not provided,
the key is unencrypted, and the only security protection is
through filesystem protections.  For Ed25519 keys, optional
parameters ciphername and rounds can be passed to specify the
desired cipher to encrypt the key with and how many rounds of
encryption to employ, respectively.

If I<$file> is not provided, returns the content that would
have been written to the key file.

=head2 $key->dump_public

Performs the inverse of I<extract_public>: takes a key I<$key>
and dumps out a textual representation of the public portion
of the key. This is used when writing public key entries to
F<known_hosts> and public identity files.

Returns the textual representation.

=head2 $key->as_blob

Returns a string representation of the public portion of the
key; this is I<not> the same as I<dump_public>, which is
intended to match the format used in F<known_hosts>, etc.
The return value of I<as_blob> is used as an intermediary in
computing other values: the key fingerprint, the known hosts
representation, etc.

=head2 $key->equal($key2)

Returns true if the public portions of I<$key> are equal to
those of I<$key2>, and false otherwise. This is used when
comparing server host keys to keys in F<known_hosts>.

=head2 $key->size

Returns the size (in bits) of the key I<$key>.

=head2 $key->fingerprint([ I<$type> ])

Returns a fingerprint of I<$key>. The default fingerprint is
a hex representation; if I<$type> is equal to C<bubblebabble>,
the Bubble Babble representation of the fingerprint is used
instead. The former uses an I<MD5> digest of the public key,
and the latter uses a I<SHA-1> digest.

=head1 AUTHOR & COPYRIGHTS

Please see the Net::SSH::Perl manpage for author, copyright,
and license information.

=cut
